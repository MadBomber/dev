#!/usr/bin/env ruby
# Smoke test S3 and SQS against a local AWS Emulator.
# Endpoint, credentials, region and CA bundle come from AWS_* env vars.
require "aws-sdk-s3"
require "aws-sdk-sqs"
require "json"

def check(label)
  result = yield
  printf "  %-38s ok  %s\n", label, result
rescue => e
  printf "  %-38s FAIL %s: %s\n", label, e.class, e.message
end

endpoint = ENV.fetch("AWS_ENDPOINT_URL")
abort "AWS_ENDPOINT_URL must point at the emulator" unless endpoint.include?("127.0.0.1")

bucket = "smoke-#{Time.now.to_i}"
s3 = Aws::S3::Client.new

print "S3 (#{endpoint})\n"
check("create_bucket")      { s3.create_bucket(bucket:).location }
check("list_buckets")       { s3.list_buckets.buckets.map(&:name).inspect }
check("put_object")         { s3.put_object(bucket:, key: "hello.txt", body: "Hello, emulator!", content_type: "text/plain").etag }
check("put_object (nested)"){ s3.put_object(bucket:, key: "dir/data.json", body: { a: 1 }.to_json).etag }
check("get_object")         { s3.get_object(bucket:, key: "hello.txt").body.read.inspect }
check("head_object")        { h = s3.head_object(bucket:, key: "hello.txt"); "#{h.content_length} bytes, #{h.content_type}" }
check("list_objects_v2 prefix=dir/") { s3.list_objects_v2(bucket:, prefix: "dir/").contents.map(&:key).inspect }
check("copy_object")        { s3.copy_object(bucket:, key: "copy.txt", copy_source: "#{bucket}/hello.txt").copy_object_result.etag }
check("presigned GET via Net::HTTP") do
  url = Aws::S3::Presigner.new(client: s3).presigned_url(:get_object, bucket:, key: "hello.txt")
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.ca_file = File.expand_path(ENV.fetch("AWS_CA_BUNDLE"))
  res = http.request(Net::HTTP::Get.new(uri))
  "#{res.code} #{res.body.inspect}"
end
check("multipart upload (2 x 5MiB)") do
  key = "big.bin"
  up = s3.create_multipart_upload(bucket:, key:)
  parts = (1..2).map do |n|
    etag = s3.upload_part(bucket:, key:, upload_id: up.upload_id, part_number: n, body: "x" * 5 * 1024 * 1024).etag
    { etag:, part_number: n }
  end
  s3.complete_multipart_upload(bucket:, key:, upload_id: up.upload_id, multipart_upload: { parts: })
  "#{s3.head_object(bucket:, key:).content_length} bytes"
end
check("get missing key -> NoSuchKey") do
  s3.get_object(bucket:, key: "nope")
  "UNEXPECTED success"
rescue Aws::S3::Errors::NoSuchKey => e
  "raised #{e.class.name.split('::').last}"
end
check("delete_objects + delete_bucket") do
  keys = s3.list_objects_v2(bucket:).contents.map { { key: it.key } }
  s3.delete_objects(bucket:, delete: { objects: keys })
  s3.delete_bucket(bucket:)
  "deleted #{keys.size} objects"
end

sqs = Aws::SQS::Client.new
# Workaround for aws/aws-emulator#25: the emulator returns sqs.<region>.amazonaws.com
# queue URLs, and aws-sdk-sqs always sends requests to the queue_url host.
local = ->(url) { "#{endpoint}#{URI(url).path}" }
print "\nSQS\n"
q = nil
check("create_queue")       { q = sqs.create_queue(queue_name: "smoke-#{Time.now.to_i}").queue_url.then(&local) }
check("list_queues")        { sqs.list_queues.queue_urls.inspect }
check("send_message")       { sqs.send_message(queue_url: q, message_body: "hi", message_attributes: { "kind" => { data_type: "String", string_value: "greeting" } }).message_id }
check("send_message_batch") { sqs.send_message_batch(queue_url: q, entries: (1..3).map { { id: "m#{it}", message_body: "batch #{it}" } }).successful.size.to_s + " sent" }
check("get_queue_attributes"){ sqs.get_queue_attributes(queue_url: q, attribute_names: ["ApproximateNumberOfMessages"]).attributes.inspect }
received = []
check("receive_message (drain)") do
  3.times do
    msgs = sqs.receive_message(queue_url: q, max_number_of_messages: 10, message_attribute_names: ["All"], wait_time_seconds: 1).messages
    received.concat(msgs)
    break if received.size >= 4
  end
  received.map(&:body).sort.inspect
end
check("message attribute round-trip") { received.find { it.body == "hi" }&.message_attributes&.dig("kind")&.string_value.inspect }
check("delete_message_batch") { sqs.delete_message_batch(queue_url: q, entries: received.each_with_index.map { |m, i| { id: "d#{i}", receipt_handle: m.receipt_handle } }).successful.size.to_s + " deleted" }
check("FIFO queue ordering") do
  fq = sqs.create_queue(queue_name: "smoke-#{Time.now.to_i}.fifo", attributes: { "FifoQueue" => "true", "ContentBasedDeduplication" => "true" }).queue_url.then(&local)
  %w[one two three].each { sqs.send_message(queue_url: fq, message_body: it, message_group_id: "g") }
  sqs.send_message(queue_url: fq, message_body: "one", message_group_id: "g") # duplicate, should be deduped
  bodies = sqs.receive_message(queue_url: fq, max_number_of_messages: 10).messages.map(&:body)
  sqs.delete_queue(queue_url: fq)
  bodies.inspect
end
check("delete_queue")       { sqs.delete_queue(queue_url: q); "ok" }
