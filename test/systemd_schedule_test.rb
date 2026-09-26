# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/systemd_schedule"
require_relative "fake_runner"

class SystemdScheduleTest < Minitest::Test
  def spec(**) = ScheduleDeclaration.normalize(:demo, **)

  def backend(home, runner = FakeRunner.new, env: {}) =
    SystemdSchedule.new(project: "My App", root: "/proj", home:, runner:, env:, user: "dewayne")

  def test_unit_slugs_the_project
    assert_equal "asgard.my-app.sync", SystemdSchedule.unit("My_App", :sync)
  end

  def test_on_calendar
    assert_equal "*-*-* 02:00:00", SystemdSchedule.on_calendar({ hour: 2, minute: 0, days: nil })
    assert_equal "Mon,Tue,Wed,Thu,Fri *-*-* 17:30:00", SystemdSchedule.on_calendar({ hour: 17, minute: 30, days: [1, 2, 3, 4, 5] })
    assert_equal "Sat,Sun *-*-* 09:05:00", SystemdSchedule.on_calendar({ hour: 9, minute: 5, days: [6, 0] })
  end

  def test_quote_escapes_backslash_quote_percent_and_dollar
    assert_equal %("a b"), SystemdSchedule.quote("a b")
    assert_equal %("say \\"hi\\" 100%% $$HOME c:\\\\x"), SystemdSchedule.quote(%(say "hi" 100% $HOME c:\\x))
  end

  def test_service_unit
    unit = SystemdSchedule.service_unit(
      description: "asgard report --title Week\\ End (proj)", arguments: ["/bin/asgard", "report", "--title", "Week End"],
      working_directory: "/proj", environment: { "PATH" => "/usr/bin", "RATE" => "5%" }, log_path: "/log/x.log"
    )
    assert_includes unit, "Type=oneshot\n"
    assert_includes unit, %(ExecStart="/bin/asgard" "report" "--title" "Week End"\n)
    assert_includes unit, %(Environment="PATH=/usr/bin"\nEnvironment="RATE=5%%"\n)
    assert_includes unit, "WorkingDirectory=/proj\n"
    assert_includes unit, "StandardOutput=append:/log/x.log\nStandardError=append:/log/x.log\n"
  end

  def test_timer_unit_calendar
    unit = SystemdSchedule.timer_unit(description: "d", service: "s.service",
                                      calendar: ScheduleDeclaration.calendar(at: %w[08:00 16:00], on: :friday))
    assert_includes unit, "OnCalendar=Fri *-*-* 08:00:00\nOnCalendar=Fri *-*-* 16:00:00\nPersistent=true\n"
    assert_includes unit, "Unit=s.service\n"
    assert_includes unit, "WantedBy=timers.target\n"
  end

  def test_timer_unit_every
    unit = SystemdSchedule.timer_unit(description: "d", service: "s.service", every: 180)
    assert_includes unit, "OnActiveSec=180\nOnUnitActiveSec=180\n"
    refute_includes unit, "OnCalendar"
  end

  def test_parse_show
    assert_equal({ "ExecMainStatus" => "0", "ExecMainExitTimestampMonotonic" => "123" },
                 SystemdSchedule.parse_show("ExecMainStatus=0\nExecMainExitTimestampMonotonic=123\n"))
  end

  def test_paths_follow_xdg
    b = backend("/h")
    assert_equal "/h/.config/systemd/user/asgard.my-app.demo.timer", b.timer_path("demo")
    assert_equal "/h/.local/state/asgard/asgard.my-app.demo.log", b.log_path("demo")
    x = backend("/h", env: { "XDG_CONFIG_HOME" => "/cfg", "XDG_STATE_HOME" => "/st" })
    assert_equal "/cfg/systemd/user/asgard.my-app.demo.service", x.service_path("demo")
    assert_equal "/st/asgard/asgard.my-app.demo.log", x.log_path("demo")
  end

  def test_install_writes_units_and_enables_timer
    Dir.mktmpdir do |home|
      runner = FakeRunner.new
      assert_equal :active, backend(home, runner).install(spec(at: "17:30", on: :weekdays), asgard: "/bin/asgard", direnv: nil)
      assert File.exist?(File.join(home, ".config/systemd/user/asgard.my-app.demo.service"))
      assert File.exist?(File.join(home, ".config/systemd/user/asgard.my-app.demo.timer"))
      assert_equal ["systemctl --user daemon-reload",
                    "systemctl --user enable asgard.my-app.demo.timer",
                    "systemctl --user restart asgard.my-app.demo.timer"], runner.commands
    end
  end

  def test_install_keeps_a_stopped_entry_stopped
    Dir.mktmpdir do |home|
      b = backend(home)
      b.install(spec(every: 60), asgard: "/a", direnv: nil)
      runner = FakeRunner.new("systemctl --user is-enabled" => ["disabled", false])
      assert_equal :stopped, backend(home, runner).install(spec(every: 60), asgard: "/a", direnv: nil)
      refute(runner.commands.any? { it.include?(" enable ") })
    end
  end

  def test_install_raises_on_systemctl_failure
    Dir.mktmpdir do |home|
      runner = FakeRunner.new("systemctl --user enable" => ["Failed to connect to bus", false])
      error  = assert_raises(ScheduleDeclaration::Error) { backend(home, runner).install(spec(every: 60), asgard: "/a", direnv: nil) }
      assert_includes error.message, "Failed to connect to bus"
    end
  end

  def test_start_stop_trigger
    runner = FakeRunner.new
    b = backend("/h", runner)
    b.stop("demo")
    b.start("demo")
    b.trigger("demo")
    assert_equal ["systemctl --user disable --now asgard.my-app.demo.timer",
                  "systemctl --user enable --now asgard.my-app.demo.timer",
                  "systemctl --user start --no-block asgard.my-app.demo.service"], runner.commands
  end

  def test_uninstall_removes_units
    Dir.mktmpdir do |home|
      b = backend(home)
      b.install(spec(every: 60), asgard: "/a", direnv: nil)
      b.uninstall("demo")
      assert_empty b.installed_names
    end
  end

  def test_status
    ran = FakeRunner.new("systemctl --user show" => ["ExecMainStatus=3\nExecMainExitTimestampMonotonic=99\n", true])
    assert_equal({ state: :active, last_exit: "3" }, backend("/h", ran).status("demo"))

    never = FakeRunner.new("systemctl --user show" => ["ExecMainStatus=0\nExecMainExitTimestampMonotonic=0\n", true])
    assert_equal({ state: :active, last_exit: nil }, backend("/h", never).status("demo"))

    stopped = FakeRunner.new("systemctl --user is-active" => ["", false], "systemctl --user is-enabled" => ["", false])
    assert_equal :stopped, backend("/h", stopped).status("demo")[:state]
  end

  def test_notes_mention_linger_only_when_off
    off = FakeRunner.new("loginctl" => ["no\n", true])
    assert_match(/enable-linger/, backend("/h", off).notes.first)
    on = FakeRunner.new("loginctl" => ["yes\n", true])
    assert_empty backend("/h", on).notes
  end
end
