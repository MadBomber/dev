# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../lib/launchd_schedule"

class LaunchdScheduleTest < Minitest::Test
  def test_label_slugs_the_project
    assert_equal "com.madbomber.asgard.my-app.sync", LaunchdSchedule.label("My_App", :sync)
  end

  def test_parse_time
    assert_equal [7, 5], LaunchdSchedule.parse_time("7:05")
    assert_raises(ArgumentError) { LaunchdSchedule.parse_time("24:00") }
    assert_raises(ArgumentError) { LaunchdSchedule.parse_time("5pm") }
  end

  def test_weekdays
    assert_equal [nil], LaunchdSchedule.weekdays(:daily)
    assert_equal [1, 2, 3, 4, 5], LaunchdSchedule.weekdays(:weekdays)
    assert_equal [6, 0], LaunchdSchedule.weekdays(:weekends)
    assert_equal [5], LaunchdSchedule.weekdays(:friday)
    assert_equal [1, 4], LaunchdSchedule.weekdays(%i[monday thursday])
    assert_raises(ArgumentError) { LaunchdSchedule.weekdays(:funday) }
  end

  def test_calendar_intervals_crosses_times_and_days
    assert_equal [{ "Hour" => 2, "Minute" => 0 }], LaunchdSchedule.calendar_intervals(at: "02:00")
    assert_equal 4, LaunchdSchedule.calendar_intervals(at: %w[09:00 17:00], on: %i[monday friday]).size
  end

  def test_normalize_requires_exactly_one_of_at_or_every
    assert_raises(ArgumentError) { LaunchdSchedule.normalize(:x) }
    assert_raises(ArgumentError) { LaunchdSchedule.normalize(:x, at: "01:00", every: 60) }
    assert_raises(ArgumentError) { LaunchdSchedule.normalize(:x, every: 0) }
    assert_equal({ "A" => "1" }, LaunchdSchedule.normalize(:x, every: 60, env: { A: 1 })[:env])
  end

  def test_normalize_splits_options_shell_style
    spec = LaunchdSchedule.normalize(:report, options: "--format md --title 'Week 39' -v", every: 60)
    assert_equal "report", spec[:task]
    assert_equal ["--format", "md", "--title", "Week 39", "-v"], spec[:args]
    assert_equal "report-format-md-title-week-39-v", spec[:name]
  end

  def test_normalize_accepts_options_as_array
    assert_equal ["--title", "Week 39"], LaunchdSchedule.normalize(:report, options: ["--title", "Week 39"], every: 60)[:args]
  end

  def test_normalize_names
    assert_equal "sync", LaunchdSchedule.normalize(:sync, every: 60)[:name]
    assert_equal "sync", LaunchdSchedule.normalize(:sync, options: "", every: 60)[:name]
    assert_equal "weekly", LaunchdSchedule.normalize(:report, options: "--period week", every: 60, as: "weekly")[:name]
    assert_raises(ArgumentError) { LaunchdSchedule.normalize(:report, options: "-v", every: 60, as: "bad name") }
  end

  def test_normalize_rejects_flags_in_the_task_name
    assert_raises(ArgumentError) { LaunchdSchedule.normalize("report -v", every: 60) }
    assert_raises(ArgumentError) { LaunchdSchedule.normalize("", every: 60) }
  end

  def test_command_line_requotes_args
    assert_equal "asgard report --title Week\\ 39", LaunchdSchedule.command_line("report", ["--title", "Week 39"])
  end

  def test_seconds_accepts_integers_and_durations
    duration = Struct.new(:in_seconds).new(180.0)
    assert_equal 90, LaunchdSchedule.seconds(90)
    assert_equal 180, LaunchdSchedule.seconds(duration)
    assert_nil LaunchdSchedule.seconds("3m")
    assert_equal 180, LaunchdSchedule.normalize(:sync, every: duration)[:every]
    assert_raises(ArgumentError) { LaunchdSchedule.normalize(:sync, every: "3m") }
  end

  def test_disabled_labels
    output = <<~OUT
      \tdisabled services = {
      \t\t"com.madbomber.asgard.temp.demo" => disabled
      \t\t"com.madbomber.asgard.temp.eod" => enabled
      \t\t"com.example.old" => true
      \t\t"com.example.other" => false
      \t}
    OUT
    assert_equal %w[com.madbomber.asgard.temp.demo com.example.old], LaunchdSchedule.disabled_labels(output)
  end

  def test_program_arguments
    assert_equal %w[/bin/asgard sync], LaunchdSchedule.program_arguments(:sync, root: "/r", asgard: "/bin/asgard")
    assert_equal ["/bin/asgard", "report", "--title", "Week 39"],
                 LaunchdSchedule.program_arguments("report", ["--title", "Week 39"], root: "/r", asgard: "/bin/asgard")
    assert_equal %w[/bin/direnv exec /r asgard report -v],
                 LaunchdSchedule.program_arguments("report", ["-v"], root: "/r", asgard: "/bin/asgard", direnv: "/bin/direnv")
  end

  def test_which
    Dir.mktmpdir do |dir|
      tool = File.join(dir, "tool")
      File.write(tool, "")
      assert_nil LaunchdSchedule.which("tool", dir)
      File.chmod(0o755, tool)
      assert_equal tool, LaunchdSchedule.which("tool", "/nonexistent:#{dir}")
    end
  end

  def test_plist_is_valid_and_escaped
    xml = LaunchdSchedule.plist(
      label: "com.madbomber.asgard.demo.sync", arguments: %w[/bin/asgard sync],
      working_directory: "/tmp/a&b", environment: { "PATH" => "/bin" },
      log_path: "/tmp/sync.log", intervals: LaunchdSchedule.calendar_intervals(at: "17:30", on: :weekdays)
    )
    assert_includes xml, "<string>/tmp/a&amp;b</string>"
    assert_includes xml, "<key>StartCalendarInterval</key>"
    _, status = Open3.capture2("plutil", "-lint", "-s", "-", stdin_data: xml)
    assert status.success?, "plutil rejected:\n#{xml}"
  end

  def test_plist_with_start_interval
    xml = LaunchdSchedule.plist(label: "l", arguments: ["/a"], working_directory: "/", environment: {},
                                log_path: "/tmp/l.log", every: 3600)
    assert_includes xml, "<key>StartInterval</key>\n  <integer>3600</integer>"
    refute_includes xml, "StartCalendarInterval"
  end
end
