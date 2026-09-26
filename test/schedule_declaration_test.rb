# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/schedule_declaration"

class ScheduleDeclarationTest < Minitest::Test
  SD = ScheduleDeclaration

  def test_parse_time
    assert_equal [7, 5], SD.parse_time("7:05")
    assert_raises(ArgumentError) { SD.parse_time("24:00") }
    assert_raises(ArgumentError) { SD.parse_time("5pm") }
  end

  def test_weekdays
    assert_nil SD.weekdays(:daily)
    assert_equal [1, 2, 3, 4, 5], SD.weekdays(:weekdays)
    assert_equal [6, 0], SD.weekdays(:weekends)
    assert_equal [5], SD.weekdays(:friday)
    assert_equal [1, 4], SD.weekdays(%i[monday thursday])
    assert_raises(ArgumentError) { SD.weekdays(:funday) }
  end

  def test_calendar_one_entry_per_time
    assert_equal [{ hour: 2, minute: 0, days: nil }, { hour: 14, minute: 0, days: nil }], SD.calendar(at: %w[02:00 14:00])
    assert_equal [{ hour: 9, minute: 15, days: [2, 4] }], SD.calendar(at: "09:15", on: %i[tuesday thursday])
  end

  def test_normalize_requires_exactly_one_of_at_or_every
    assert_raises(ArgumentError) { SD.normalize(:x) }
    assert_raises(ArgumentError) { SD.normalize(:x, at: "01:00", every: 60) }
    assert_raises(ArgumentError) { SD.normalize(:x, every: 0) }
    assert_equal({ "A" => "1" }, SD.normalize(:x, every: 60, env: { A: 1 })[:env])
  end

  def test_normalize_splits_options_shell_style
    spec = SD.normalize(:report, options: "--format md --title 'Week 39' -v", every: 60)
    assert_equal "report", spec[:task]
    assert_equal ["--format", "md", "--title", "Week 39", "-v"], spec[:args]
    assert_equal "report-format-md-title-week-39-v", spec[:name]
  end

  def test_normalize_accepts_options_as_array
    assert_equal ["--title", "Week 39"], SD.normalize(:report, options: ["--title", "Week 39"], every: 60)[:args]
  end

  def test_normalize_names
    assert_equal "sync", SD.normalize(:sync, every: 60)[:name]
    assert_equal "weekly", SD.normalize(:report, options: "--period week", every: 60, as: "weekly")[:name]
    assert_raises(ArgumentError) { SD.normalize(:report, options: "-v", every: 60, as: "bad name") }
  end

  def test_normalize_rejects_flags_in_the_task_name
    assert_raises(ArgumentError) { SD.normalize("report -v", every: 60) }
    assert_raises(ArgumentError) { SD.normalize("", every: 60) }
  end

  def test_seconds_accepts_integers_and_durations
    duration = Struct.new(:in_seconds).new(180.0)
    assert_equal 90, SD.seconds(90)
    assert_equal 180, SD.seconds(duration)
    assert_nil SD.seconds("3m")
    assert_equal 180, SD.normalize(:sync, every: duration)[:every]
    assert_raises(ArgumentError) { SD.normalize(:sync, every: "3m") }
  end

  def test_slug
    assert_equal "my-app", SD.slug("My_App")
  end

  def test_command_line_requotes_args
    assert_equal "asgard report --title Week\\ 39", SD.command_line("report", ["--title", "Week 39"])
  end

  def test_describe
    assert_equal "every 60s", SD.describe(every: 60)
    assert_equal "17:30 weekdays", SD.describe(at: "17:30", on: :weekdays)
  end

  def test_environment_merges_path_and_env
    assert_equal({ "PATH" => "/bin", "A" => "1" }, SD.environment({ env: { "A" => "1" } }, "/bin"))
  end

  def test_which
    Dir.mktmpdir do |dir|
      tool = File.join(dir, "tool")
      File.write(tool, "")
      assert_nil SD.which("tool", dir)
      File.chmod(0o755, tool)
      assert_equal tool, SD.which("tool", "/nonexistent:#{dir}")
    end
  end

  def test_program_arguments
    assert_equal %w[/bin/asgard sync], SD.program_arguments(:sync, root: "/r", asgard: "/bin/asgard")
    assert_equal ["/bin/asgard", "report", "--title", "Week 39"],
                 SD.program_arguments("report", ["--title", "Week 39"], root: "/r", asgard: "/bin/asgard")
    assert_equal %w[/bin/direnv exec /r asgard report -v],
                 SD.program_arguments("report", ["-v"], root: "/r", asgard: "/bin/asgard", direnv: "/bin/direnv")
  end

  def test_runner_reports_missing_commands_as_failure
    out, ok = SD::RUNNER.call("definitely-not-a-command-xyz")
    refute ok
    refute_empty out
  end
end
