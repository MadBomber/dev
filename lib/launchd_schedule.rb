# frozen_string_literal: true
# macOS backend for schedule.loki: each declaration becomes a launchd user
# agent (~/Library/LaunchAgents/com.madbomber.asgard.<project>.<name>.plist).
# launchd runs a calendar job missed while the Mac slept as soon as it wakes.
# Implements the backend API documented in schedule_declaration.rb.

require "fileutils"
require_relative "schedule_declaration"

class LaunchdSchedule
  LABEL_PREFIX = "com.madbomber.asgard"

  # ---- pure helpers -------------------------------------------------------

  def self.label_prefix(project) = "#{LABEL_PREFIX}.#{ScheduleDeclaration.slug(project)}."

  def self.label(project, name) = "#{label_prefix(project)}#{name}"

  # One StartCalendarInterval entry per (time, weekday) pair.
  def self.calendar_intervals(at:, on: :daily)
    ScheduleDeclaration.calendar(at:, on:).flat_map do |entry|
      (entry[:days] || [nil]).map { |day| { "Hour" => entry[:hour], "Minute" => entry[:minute], "Weekday" => day }.compact }
    end
  end

  # Labels marked disabled in `launchctl print-disabled` output
  # ("label" => disabled, or "label" => true on older macOS).
  def self.disabled_labels(output) = output.scan(/"([^"]+)"\s*=>\s*(disabled|true)\b/).map(&:first)

  def self.plist(label:, arguments:, working_directory:, environment:, log_path:, intervals: nil, every: nil)
    dict = {
      "Label"                => label,
      "ProgramArguments"     => arguments,
      "WorkingDirectory"     => working_directory,
      "EnvironmentVariables" => environment,
      "StandardOutPath"      => log_path,
      "StandardErrorPath"    => log_path
    }
    every ? dict["StartInterval"] = every : dict["StartCalendarInterval"] = intervals

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      #{to_xml(dict)}
      </plist>
    XML
  end

  def self.to_xml(value, indent = "")
    case value
    in Hash
      body = value.flat_map { |k, v| ["#{indent}  <key>#{escape(k)}</key>", to_xml(v, "#{indent}  ")] }
      ["#{indent}<dict>", *body, "#{indent}</dict>"].join("\n")
    in Array
      ["#{indent}<array>", *value.map { to_xml(it, "#{indent}  ") }, "#{indent}</array>"].join("\n")
    in Integer
      "#{indent}<integer>#{value}</integer>"
    in true | false
      "#{indent}<#{value}/>"
    else
      "#{indent}<string>#{escape(value)}</string>"
    end
  end

  def self.escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

  # ---- backend API --------------------------------------------------------

  def initialize(project:, root:, home: Dir.home, runner: ScheduleDeclaration::RUNNER, uid: Process.uid)
    @project = project
    @root    = root
    @home    = home
    @runner  = runner
    @domain  = "gui/#{uid}"
  end

  def scheduler = "launchd"

  def label(name) = self.class.label(@project, name)

  def plist_path(name) = File.join(@home, "Library", "LaunchAgents", "#{label(name)}.plist")

  def log_path(name) = File.join(@home, "Library", "Logs", "asgard", "#{label(name)}.log")

  def files(spec, asgard:, direnv:)
    name = spec[:name]
    plist = self.class.plist(
      label:             label(name),
      arguments:         ScheduleDeclaration.program_arguments(spec[:task], spec[:args], root: @root, asgard:, direnv:),
      working_directory: @root,
      environment:       ScheduleDeclaration.environment(spec),
      log_path:          log_path(name),
      intervals:         spec[:every] ? nil : self.class.calendar_intervals(at: spec[:at], on: spec[:on]),
      every:             spec[:every]
    )
    { plist_path(name) => plist }
  end

  def install(spec, asgard:, direnv:)
    name = spec[:name]
    FileUtils.mkdir_p [File.dirname(plist_path(name)), File.dirname(log_path(name))]
    files(spec, asgard:, direnv:).each { |path, content| File.write(path, content) }
    run! "plutil", "-lint", "-s", plist_path(name)
    unload(name)
    return :stopped if stopped?(name)

    run! "launchctl", "bootstrap", @domain, plist_path(name)
    :active
  end

  def uninstall(name)
    unload(name)
    run "launchctl", "enable", target(name) # clear any stop
    FileUtils.rm_f(plist_path(name))
  end

  def start(name)
    run! "launchctl", "enable", target(name)
    run! "launchctl", "bootstrap", @domain, plist_path(name) unless loaded?(name)
  end

  def stop(name)
    run! "launchctl", "disable", target(name)
    unload(name)
  end

  def trigger(name) = run!("launchctl", "kickstart", target(name))

  def installed_names
    prefix = self.class.label_prefix(@project)
    Dir.glob(plist_path("*")).map { File.basename(it, ".plist").delete_prefix(prefix) }.sort
  end

  def status(name)
    out, ok = run("launchctl", "print", target(name))
    return { state: stopped?(name) ? :stopped : :not_loaded, last_exit: nil } unless ok

    code = out[/last exit code = (\d+)/, 1]
    { state: :active, last_exit: code }
  end

  def notes = []

  private

  def target(name) = "#{@domain}/#{label(name)}"

  def loaded?(name) = run("launchctl", "print", target(name)).last

  def stopped?(name)
    out, = run("launchctl", "print-disabled", @domain)
    self.class.disabled_labels(out).include?(label(name))
  end

  # bootout returns before the job is fully gone; bootstrapping the same
  # label too soon fails with "Input/output error", so wait for it.
  def unload(name)
    return unless loaded?(name)

    run "launchctl", "bootout", target(name)
    20.times do
      break unless loaded?(name)

      sleep 0.1
    end
  end

  def run(*argv) = @runner.call(*argv)

  def run!(*argv)
    out, ok = run(*argv)
    raise ScheduleDeclaration::Error, "#{argv.join(' ')} failed: #{out.strip}" unless ok

    out
  end
end
