# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../lib/launchd_schedule"
require_relative "fake_runner"

class LaunchdScheduleTest < Minitest::Test
  def spec(**) = ScheduleDeclaration.normalize(:demo, **)

  def backend(home, runner = FakeRunner.new) = LaunchdSchedule.new(project: "My App", root: "/proj", home:, runner:, uid: 501)

  def test_label_slugs_the_project
    assert_equal "com.madbomber.asgard.my-app.sync", LaunchdSchedule.label("My_App", :sync)
  end

  def test_calendar_intervals_cross_times_and_days
    assert_equal [{ "Hour" => 2, "Minute" => 0 }], LaunchdSchedule.calendar_intervals(at: "02:00")
    assert_equal 4, LaunchdSchedule.calendar_intervals(at: %w[09:00 17:00], on: %i[monday friday]).size
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

  def test_plist_is_valid_and_escaped
    xml = LaunchdSchedule.plist(
      label: "com.madbomber.asgard.demo.sync", arguments: %w[/bin/asgard sync],
      working_directory: "/tmp/a&b", environment: { "PATH" => "/bin" },
      log_path: "/tmp/sync.log", intervals: LaunchdSchedule.calendar_intervals(at: "17:30", on: :weekdays)
    )
    assert_includes xml, "<string>/tmp/a&amp;b</string>"
    assert_includes xml, "<key>StartCalendarInterval</key>"
    _, status = Open3.capture2("plutil", "-lint", "-s", "-", stdin_data: xml) if system("which -s plutil")
    assert status.success?, "plutil rejected:\n#{xml}" if status
  end

  def test_plist_with_start_interval
    xml = LaunchdSchedule.plist(label: "l", arguments: ["/a"], working_directory: "/", environment: {},
                                log_path: "/tmp/l.log", every: 3600)
    assert_includes xml, "<key>StartInterval</key>\n  <integer>3600</integer>"
    refute_includes xml, "StartCalendarInterval"
  end

  def test_paths_live_under_home
    b = backend("/h")
    assert_equal "/h/Library/LaunchAgents/com.madbomber.asgard.my-app.demo.plist", b.plist_path("demo")
    assert_equal "/h/Library/Logs/asgard/com.madbomber.asgard.my-app.demo.log", b.log_path("demo")
  end

  def test_install_writes_plist_and_bootstraps
    Dir.mktmpdir do |home|
      runner = FakeRunner.new("launchctl print gui" => ["", false])
      state  = backend(home, runner).install(spec(every: 60), asgard: "/bin/asgard", direnv: nil)
      assert_equal :active, state
      assert File.exist?(File.join(home, "Library/LaunchAgents/com.madbomber.asgard.my-app.demo.plist"))
      assert(runner.commands.any? { it.start_with?("launchctl bootstrap gui/501 ") })
    end
  end

  def test_install_keeps_a_stopped_entry_stopped
    Dir.mktmpdir do |home|
      runner = FakeRunner.new(
        "launchctl print gui"      => ["", false],
        "launchctl print-disabled" => [%(\t"com.madbomber.asgard.my-app.demo" => disabled\n), true]
      )
      assert_equal :stopped, backend(home, runner).install(spec(every: 60), asgard: "/bin/asgard", direnv: nil)
      refute(runner.commands.any? { it.include?("bootstrap") })
    end
  end

  def test_install_raises_on_launchctl_failure
    Dir.mktmpdir do |home|
      runner = FakeRunner.new("launchctl print gui" => ["", false], "launchctl bootstrap" => ["Bootstrap failed: 5", false])
      assert_raises(ScheduleDeclaration::Error) { backend(home, runner).install(spec(every: 60), asgard: "/a", direnv: nil) }
    end
  end

  def test_stop_and_start
    runner = FakeRunner.new("launchctl print gui" => ["", false])
    b = backend("/h", runner)
    b.stop("demo")
    b.start("demo")
    assert_equal ["launchctl disable gui/501/com.madbomber.asgard.my-app.demo",
                  "launchctl print gui/501/com.madbomber.asgard.my-app.demo",
                  "launchctl enable gui/501/com.madbomber.asgard.my-app.demo",
                  "launchctl print gui/501/com.madbomber.asgard.my-app.demo",
                  "launchctl bootstrap gui/501 /h/Library/LaunchAgents/com.madbomber.asgard.my-app.demo.plist"], runner.commands
  end

  def test_status
    active = FakeRunner.new("launchctl print gui" => ["state = not running\n\tlast exit code = 0\n", true])
    assert_equal({ state: :active, last_exit: "0" }, backend("/h", active).status("demo"))

    never = FakeRunner.new("launchctl print gui" => ["last exit code = (never exited)\n", true])
    assert_equal({ state: :active, last_exit: nil }, backend("/h", never).status("demo"))

    stopped = FakeRunner.new("launchctl print gui"      => ["", false],
                             "launchctl print-disabled" => [%("com.madbomber.asgard.my-app.demo" => disabled), true])
    assert_equal :stopped, backend("/h", stopped).status("demo")[:state]
  end

  def test_installed_names
    Dir.mktmpdir do |home|
      dir = File.join(home, "Library/LaunchAgents")
      FileUtils.mkdir_p(dir)
      %w[com.madbomber.asgard.my-app.b com.madbomber.asgard.my-app.a com.madbomber.asgard.other.c].each do
        File.write(File.join(dir, "#{it}.plist"), "")
      end
      assert_equal %w[a b], backend(home).installed_names
    end
  end
end
