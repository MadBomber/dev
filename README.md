# dev — Shared Asgard Task Libraries

This repo is the common layer of development tasks shared by the repos in the
`~/sandbox/git_repos/madbomber/` workspace. It contains no application code —
just `.loki` task files for [Asgard](https://github.com/madbomber/asgard)
(a Thor-based task runner) plus a strict RuboCop overlay. See the
[Asgard documentation website](https://madbomber.github.io/asgard) for the
full `.loki` file DSL and feature set.

To use it, clone this repo as a peer-level directory to your projects — or
anywhere higher up in their filesystem chain.  Here is how I
have it setup:

```
~/sandbox/git_repos/madbomber/
├── dev/            # this repo
├── my_gem/         # my projects, as peers (or deeper below)
└── my_rails_app/
```

Individual project repos do not copy these tasks; they import them with
`import_up`, which searches from the project directory upward through its
parents until it finds the named file — so no relative paths to maintain:

```ruby
# a gem repo's .loki might look like this
import_up "dev/gem_tasks.loki"
import_up "dev/quality.loki"
import_up "dev/git.loki"
import_up "dev/quality_rails.loki" if ENV["RAILS_ROOT"]   # Rails apps only
```

Because every `.loki` file simply reopens `class Tasks`, imported tasks merge
into one command set, and a repo may override any task locally (e.g. a repo
whose `push` also pushes tags).

## Contents

| File | Provides |
|------|----------|
| `gem_tasks.loki` | Gem lifecycle: `console`, `build`, `install`, `release` |
| `quality.loki` | The `quality` gate and the `*_check` tasks it runs |
| `quality_rails.loki` | Rails-only checks: Brakeman, RailsBestPractices, ActiveRecordDoctor |
| `git.loki` | Per-repo git basics: `push`, `pull` (ff-only), `fetch` |
| `doc_tasks.loki` | Documentation tasks (`tocer`, `mkdocs` build/serve), enabled per repo |
| `status_report.loki` | End-of-week client status reporting: `daily_summary`, `weekly_report` |
| `iterm_tasks.loki` | Terminal fixes: `half_duplex_screen_fix`, `clear_scroll_back_buffer` |
| `schedule.loki` | Scheduled tasks via launchd (macOS) or systemd (Linux): `schedule` helper plus `asgard schedule preview|install|list|start|stop|trigger|log|remove` |
| `rubocop-strict.yml` | Cops that must always fire, regardless of `.rubocop_todo.yml` or inline directives |

### gem_tasks.loki

Universal gem lifecycle tasks. Uses the `gem` command directly — no rake
dependency. `@@gem_name` defaults to the gemspec's basename (falling back to
the directory name); a repo may set it earlier if it differs. A `gem_version`
helper reads `VERSION` from `lib/**/version.rb`.

- `build` — builds the gemspec into `pkg/<name>-<version>.gem`
- `install` — builds, then `gem install --local`
- `release` — runs the `quality` gate and `build`, confirms (skip with `-y`),
  requires a clean working tree and an unused `v<version>` tag, then tags,
  pushes, and `gem push`es to RubyGems

### quality.loki

The heart of the shared layer. `quality` discovers every task whose name ends
in `_check` at run time — from this file, from `quality_rails.loki`, or from a
repo's own `.loki` — and runs them all in parallel, printing a colorized
PASS/FAIL/WARN/SKIP summary. Adding a new gate anywhere is just defining
another `*_check` task; nothing needs to be redeclared.

Gates defined here: tests, RuboCop, Flog complexity, Flay duplication, Reek
smells, typos, ERBLint, Fasterer, bundler-audit, and ArchSpec. Each check
writes its full output to a `*_output.txt` file in the repo being checked and
prints a one-line summary. Checks whose tool or config is absent report SKIP
rather than failing; only FAIL blocks. Companion `*_fix` tasks
(`rubocop_fix`, `typos_fix`) auto-correct what their checks flag.

### quality_rails.loki

Rails-specific `*_check` gates, gated on `RAILS_ROOT` (set in a Rails repo's
`.envrc`) rather than `defined?(Rails)`, since Asgard runs outside the app's
process. Once imported, its checks are picked up by `quality` automatically.

### status_report.loki

Personal end-of-week client status reporting. `daily_summary` discovers
every `*_collect` task the same way `quality` discovers `*_check` tasks,
runs them, and writes the day's activity to `notes/_status/<date>.md`
under `RR`. `weekly_report` reads Mon–Fri's daily files and pipes them
through headless Claude Code (`claude -p`) to produce a client-facing
Markdown report at `notes/_status/week-of-<monday>.md`.

Each collector is best-effort and never fails the run — a missing tool or
unset env var just prints a SKIP line instead of aborting the others:

- `notes_collect` — `_notes.txt` journal entries (no config needed)
- `git_collect` — `git log`, scoped to `git config user.email`
- `github_collect` — needs `gh` authenticated (`gh auth status`)
- `jira_collect` — needs `JIRA_SITE`, `JIRA_PROJECT`, `JIRA_USER_EMAIL`,
  `JIRA_API_KEY`
- `claude_sessions_collect` — reads `~/.claude/projects/<repo>/*.jsonl`
- `shell_history_collect` — needs `HISTTIMEFORMAT` set so
  `~/.bash_history` carries timestamps
- `calendar_collect` — needs `icalBuddy` (`brew install ical-buddy`)

Add a source by defining another `*_collect` task; nothing else needs to
be redeclared.

### schedule.loki

Runs asgard tasks on a schedule, declared right in the repo's own `.loki`,
using the platform's own scheduler: **launchd** on macOS, **systemd user
timers** on Linux. Both run a calendar job missed while the machine slept as
soon as it wakes. Needs the `activesupport` gem installed (for
`every: 3.minutes`-style durations).

```ruby
# .loki
import_up "dev/schedule.loki"

class Tasks
  schedule :daily_summary, at: "17:30", on: :weekdays
  schedule :weekly_report, at: "16:00", on: :friday
  schedule :sync,          every: 1.hour               # or plain seconds: 3600

  # The task's own flags go in options: (split shell-style, quotes kept)
  schedule :report, options: "-v",                                at: "08:00", on: :weekdays
  schedule :report, options: "--period week --title 'Week End'", at: "16:30", on: :friday, as: "weekly_report"
end
```

`on:` takes `:daily` (default), `:weekdays`, `:weekends`, a day, or an array
of days; `at:` may be an array of times; `options:` may also be an array of
words; `env:` adds literal variables. Each entry has a name, used by the
subcommands below: the task name, a slug of the task plus its options
(`:report, options: "-v"` → `report-v`), or whatever `as:` gives. So one
task can be scheduled several times with different flags; two different
entries with the same name raise.

`schedule` is also a command with subcommands (same on both platforms):

- `asgard schedule preview` — prints the job files that would be installed
- `asgard schedule install` — writes and loads one job per declaration; removes jobs no longer declared
- `asgard schedule list` — installed entries, their command, schedule, state (active/stopped), and last exit status
- `asgard schedule stop NAME` — stops one entry; it stays stopped across reboots and `install` until started
- `asgard schedule start NAME` — starts a stopped entry, or installs and starts just that declared entry
- `asgard schedule trigger NAME` — runs an installed entry now, under the scheduler's environment
- `asgard schedule log NAME` — prints the entry's log to STDOUT; `-f` keeps following it
- `asgard schedule remove` — unloads and deletes all of this project's jobs

Jobs run `asgard <task> [options]` from the directory holding `.loki` with the
PATH captured at install time. If the repo has a `.envrc`, jobs run under
`direnv exec` so `RR`, API keys, etc. load at run time and never land in the
job files. Re-run `asgard schedule install` after changing declarations or
your PATH.

| | macOS (launchd) | Linux (systemd) |
|---|---|---|
| Job files | `~/Library/LaunchAgents/com.madbomber.asgard.<project>.<name>.plist` | `~/.config/systemd/user/asgard.<project>.<name>.{service,timer}` |
| Logs | `~/Library/Logs/asgard/` | `~/.local/state/asgard/` |
| Stop | `launchctl disable` | `systemctl --user disable --now` |
| Caveat | runs only while you're logged in | runs only while you're logged in unless `loginctl enable-linger`; needs systemd 240+ |

Code layout: `lib/schedule_declaration.rb` (declarations, platform-neutral,
and the backend API both platforms implement), `lib/launchd_schedule.rb`
(macOS only), `lib/systemd_schedule.rb` (Linux only). Tests:
`ruby test/<name>_test.rb` for each; both backends' tests run on any
platform because system commands go through an injectable runner.

### rubocop-strict.yml

A small overlay a repo's `.rubocop.yml` can `inherit_from` to guarantee that
certain cops (`Lint/Debugger`, `Security/Eval`, `Lint/SuppressedException`)
stay enabled no matter what `.rubocop_todo.yml` or inline directives say.

## Conventions

- Every file reopens `class Tasks`; Asgard supplies the DSL
  (`desc`, `depends_on`, `option`, `helper`, `sh`, `no_commands`).
- Check tasks return `:pass`, `:fail`, `:warn`, or `:skip` — `quality`
  aggregates these into its summary, and only `:fail` is blocking.
- Tasks here must stay universal. Anything repo-specific belongs in that
  repo's own `.loki`, which can override or extend what it imports.
- `asgard/` in this workspace mirrors these files and is the golden pattern
  they follow.

## Contributing

Bug reports and pull requests are welcome at
https://github.com/MadBomber/dev. Have a task or quality gate that would be
useful across many Ruby projects? Open a PR — keep it universal (see
Conventions above), and name any new gate `*_check` so the `quality` task
picks it up automatically. Ideas and feedback are just as welcome as code;
feel free to open an issue to start a discussion.

## License

Released under the [MIT License](LICENSE).
