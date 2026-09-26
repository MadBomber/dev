# frozen_string_literal: true

# Stands in for ScheduleDeclaration::RUNNER: records each argv and answers
# from a table of { argv_prefix_string => [output, success?] } (longest
# matching prefix wins; unmatched commands succeed with no output).
class FakeRunner
  attr_reader :calls

  def initialize(responses = {})
    @responses = responses
    @calls     = []
  end

  def call(*argv)
    @calls << argv
    line = argv.join(" ")
    key  = @responses.keys.select { line.start_with?(it) }.max_by(&:length)
    key ? @responses[key] : ["", true]
  end

  def to_proc = method(:call).to_proc

  def commands = @calls.map { it.join(" ") }
end
