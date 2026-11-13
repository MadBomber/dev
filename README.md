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
| `doc_tasks.loki` | Documentation site tasks, for a repo with `mkdocs.yml` or `bridgetown.config.yml`: `doc install`, `doc build`, `doc serve`, `doc open` |
| `status_report.loki` | End-of-week client status reporting: `daily_summary`, `weekly_report` |
| `iterm_tasks.loki` | Terminal fixes: `half_duplex_screen_fix`, `clear_scroll_back_buffer` |
| `branch_report.loki` | `branch_report [DAYS]`: read-only table of every local and remote branch (ahead/behind and merged measured against `origin/<default>` as of the last fetch, else the local default), then the ones idle (or merged and idle) over DAYS, default 30 |
| `db_doc.loki` | [tbls](https://github.com/k1LoW/tbls) schema docs into `notes/dbdoc` (needs Postgres up on localhost:5432; `DB_DOC_DSN` overrides the default vbr_development DSN): `db_doc`, `db_doc_diff`, `db_doc_mermaid`, `db_doc_open`, `db_doc_clean` |
| `rubocop-strict.yml` | Cops kept enabled with no exclusions over `.rubocop_todo.yml` (when inherited after it; see below) |

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
smells, typos, ERBLint, Fasterer, SCRAP test structure (scrap4rb),
bundler-audit, and ArchSpec. Fasterer and SCRAP are advisory: their findings
report WARN, never FAIL. Each check writes its full output to a `*_output.txt`
file in the repo being checked and prints a one-line summary. Checks whose
tool or config is absent report SKIP rather than failing; only FAIL blocks. Companion `*_fix` tasks
(`rubocop_fix`, `typos_fix`) auto-correct what their checks flag.

Reek fails only on files that are new to, or worse than, the per-file smell
counts grandfathered in `.quality/reek_baseline.txt`. Its companion task,
`reek_baseline`, regenerates that file from the current smells: run
`asgard reek_baseline` when a regression is intentional (or to ratchet the
counts down after a cleanup).

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

### Scheduled tasks

Scheduling is built into asgard: declare
`schedule :task, at: "17:30", on: :weekdays` in a `.loki` and manage the
entries with `asgard schedule`. See
[Scheduled Tasks](https://madbomber.github.io/asgard/schedule/).

The old `dev/schedule.loki` has been removed. To move a repo off it (these
steps assume asgard 0.6.0):

1. Fix declarations the built-in `schedule` reads differently, so the
   `.loki` will load without the old file. `every: 1.hour` raises unless the `.loki` requires
   `active_support/core_ext/integer/time` itself (or write `every: 3600`);
   `every:` with `on:` is rejected; and entry names built from `options:`
   may gain a hash suffix (pass `as:` to keep a fixed name). asgard's
   CHANGELOG lists the details.
2. Delete `import_up "dev/schedule.loki"` from the `.loki`.
3. Remove the jobs the old file installed. They are filed under the plain
   project name, which 0.6.0 does not treat as this project's: find them
   with `asgard schedule list --all` and run
   `asgard schedule remove <project>/<name>` for each
   (`asgard schedule prune` clears any whose directory is gone). Do this in
   every such repo before step 4 in any of them.
4. Run `asgard schedule install`.

### rubocop-strict.yml

A small overlay a repo's `.rubocop.yml` can `inherit_from` to keep certain
cops (`Lint/Debugger`, `Security/Eval`, `Lint/SuppressedException`) enabled
with no file exclusions, overriding `.rubocop_todo.yml`. The guarantee has
limits:

- List it **after** `.rubocop_todo.yml` in `inherit_from`
  (`inherit_from: [.rubocop_todo.yml, ../dev/rubocop-strict.yml]`); later
  entries win, so listed first the todo file's exclusions still apply.
- Its `Exclude: []` clears nothing when the config sets
  `inherit_mode: merge: [Exclude]`; inherited exclusions are merged instead.
- Inline `# rubocop:disable` comments are still honoured unless RuboCop runs
  with `--ignore-disable-comments`.

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
