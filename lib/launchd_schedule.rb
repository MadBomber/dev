# frozen_string_literal: true
# Pure helpers behind schedule.loki: turn a `schedule` declaration into a
# launchd agent plist. Nothing here calls launchctl or writes files, so each
# method can be tested on its own.

require "shellwords"

module LaunchdSchedule
  LABEL_PREFIX = "com.madbomber.asgard"

  # launchd numbers weekdays 0 (Sunday) through 6 (Saturday).
  DAYS = %i[sunday monday tuesday wednesday thursday friday saturday].freeze

  DAY_GROUPS = {
    weekdays: %i[monday tuesday wednesday thursday friday],
    weekends: %i[saturday sunday]
  }.freeze

  module_function

  # Validates a declaration and returns it as a plain Hash. options: is the
  # task's command-line options as a String, split shell-style with quotes
  # respected ("--period week --title 'Week End'"), or an Array of words.
  # Exactly one of at: ("HH:MM" or an Array of them, with on:) or every:
  # (seconds) is required. as: names the entry (and its launchd label).
  def normalize(task, options: nil, at: nil, on: :daily, every: nil, env: {}, as: nil)
    task = task.to_s
    raise ArgumentError, "schedule: task name #{task.inspect} must be a single word; put its flags in options:" unless task.match?(/\A[\w:-]+\z/)
    raise ArgumentError, "schedule :#{task} needs either at: or every:, not both" unless at.nil? ^ every.nil?

    if every
      every = seconds(every)
      raise ArgumentError, "schedule :#{task} every: must be a positive number of seconds or a Duration (3.minutes)" unless every&.positive?
    else
      calendar_intervals(at:, on:) # raises on a bad time or day
    end

    args = options.is_a?(Array) ? options.map(&:to_s) : Shellwords.split(options.to_s)
    { name: entry_name(task, args, as), task:, args:, at:, on:, every:, env: env.to_h { |k, v| [k.to_s, v.to_s] } }
  end

  # Integer seconds from an Integer or anything Duration-like (ActiveSupport's
  # 3.minutes responds to in_seconds); nil for anything else.
  def seconds(value)
    case value
    in Integer then value
    else value.respond_to?(:in_seconds) ? value.in_seconds.to_i : nil
    end
  end

  # The task alone, or a slug of the whole command when it has arguments,
  # so one task can be scheduled more than once with different flags.
  def entry_name(task, args, as = nil)
    name = (as || (args.empty? ? task : slug([task, *args].join(" ")))).to_s
    raise ArgumentError, "schedule as: #{name.inspect} may only contain letters, digits, _ . -" unless name.match?(/\A[\w.-]+\z/)

    name
  end

  # For display: the command line the job runs.
  def command_line(task, args = []) = Shellwords.join(["asgard", task.to_s, *args])

  def slug(name) = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")

  def project_prefix(project) = "#{LABEL_PREFIX}.#{slug(project)}."

  def label(project, task) = "#{project_prefix(project)}#{task}"

  # "17:30" => [17, 30]
  def parse_time(time)
    match = /\A(\d{1,2}):(\d{2})\z/.match(time.to_s) or
      raise ArgumentError, %(at: expects "HH:MM" (got #{time.inspect}))
    hour, minute = match[1].to_i, match[2].to_i
    raise ArgumentError, "at: #{time.inspect} is not a valid time" unless hour <= 23 && minute <= 59

    [hour, minute]
  end

  # :daily => [nil]; :weekdays => [1, 2, 3, 4, 5]; :friday => [5];
  # %i[monday thursday] => [1, 4]
  def weekdays(on)
    return [nil] if on.to_s == "daily"

    names = DAY_GROUPS.fetch(on.is_a?(Array) ? nil : on.to_sym) { Array(on) }
    names.map do |day|
      DAYS.index(day.to_sym) or raise ArgumentError, "on: unknown day #{day.inspect}"
    end
  end

  # One StartCalendarInterval entry per (time, weekday) pair.
  def calendar_intervals(at:, on: :daily)
    Array(at).flat_map do |time|
      hour, minute = parse_time(time)
      weekdays(on).map { |day| { "Hour" => hour, "Minute" => minute, "Weekday" => day }.compact }
    end
  end

  def describe(at: nil, on: :daily, every: nil, **)
    return "every #{every}s" if every

    "#{Array(at).join(', ')} #{Array(on).join(', ')}"
  end

  # Labels marked disabled in `launchctl print-disabled` output
  # ("label" => disabled, or "label" => true on older macOS).
  def disabled_labels(output)
    output.scan(/"([^"]+)"\s*=>\s*(disabled|true)\b/).map(&:first)
  end

  # First executable named +command+ on +path+ (a PATH-style String), or nil.
  def which(command, path)
    path.to_s.split(File::PATH_SEPARATOR)
        .map { File.join(it, command) }
        .find { File.file?(it) && File.executable?(it) }
  end

  # launchd needs an absolute program. With direnv, the repo's .envrc
  # (RR, API keys, ...) is loaded at run time instead of being copied into
  # the plist, and direnv finds asgard on the plist's PATH.
  # Each argument is its own array element, so no shell re-splits them.
  def program_arguments(task, args = [], root:, asgard:, direnv: nil)
    argv = [task.to_s, *args.map(&:to_s)]
    direnv ? [direnv, "exec", root, "asgard", *argv] : [asgard, *argv]
  end

  def plist(label:, arguments:, working_directory:, environment:, log_path:, intervals: nil, every: nil)
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

  def to_xml(value, indent = "")
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

  def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end
