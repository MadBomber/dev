# frozen_string_literal: true

# dev/quality/test_progress_listener.rb
#
# Loaded into each parallel_rspec process by quality.loki's test_check
# (SPEC_OPTS="--require <this file>"), never by the app itself. Each process
# writes "done total" to $TEST_PROGRESS_DIR/<process>.txt as its examples
# finish, so the quality board can draw one progress bar for the whole run.
#
# It listens on RSpec's reporter instead of registering as a formatter:
# add_formatter would count as the project's formatter choice, so a project
# with no --format of its own would lose RSpec's default one and, with it,
# the failure details and the "N examples, M failures" line. Registers only
# when TEST_PROGRESS_DIR is set, so a stray require is a no-op.
class TestProgressListener
  def initialize(dir: ENV.fetch("TEST_PROGRESS_DIR"), process: ENV.fetch("TEST_ENV_NUMBER", ""))
    @path = File.join(dir, "#{process.empty? ? '1' : process}.txt")
    @done = 0
  end

  def start(notification)
    @total = notification.count
    write
  end

  def example_finished(_notification)
    @done += 1
    write
  end

  private

  # Write-then-rename, so the poller never reads a half-written file.
  def write
    File.write("#{@path}.tmp", "#{@done} #{@total}")
    File.rename("#{@path}.tmp", @path)
  end
end

if ENV["TEST_PROGRESS_DIR"]
  RSpec.configure { it.reporter.register_listener(TestProgressListener.new, :start, :example_finished) }
end
