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
import_up "dev/rails/*.loki" if ENV["RAILS_ROOT"]          # Rails apps only
```

To take every general task file at once, import `dev/.loki` instead. It
imports each `*.loki` file in this directory, including any added later:

```ruby
import_up "dev/.loki"
```

That loads all of them whether or not they fit the repo: a repo that
isn't a gem still gets `build`, `install` and `release`. Import files one
by one, as above, to keep a repo's command list to what it uses.

Two subdirectories hold task files that only some repos want: `rails/`
for Rails apps and `client/` for client projects. Neither `dev/.loki`
nor a `dev/*.loki` glob reaches into them, so a repo that wants them
imports them itself:

```ruby
import_up "dev/rails/*.loki"    # Rails apps
import_up "dev/client/*.loki"   # client projects
```

`quality_rails.loki`, `db_doc.loki` and `status_report.loki` used to sit
at the top level. A repo that imports one by its old path
(`dev/quality_rails.loki`, `dev/db_doc.loki`, `dev/status_report.loki`)
must switch to the `dev/rails/` or `dev/client/` path.

Because every `.loki` file simply reopens `class Tasks`, imported tasks merge
into one command set, and a repo may override any task locally (e.g. a repo
whose `push` also pushes tags).

## Requirements

- **asgard 0.6.0 or later**, which needs **Ruby 4.0 or later**. 0.6.0 adds
  the background jobs `doc serve` uses and the built-in scheduler these
  files assume (see Scheduled tasks below).
- **flay and reek go in asgard's own Ruby.** `flay_check`, `reek_check` and
  `reek_baseline` load them in-process, so run `gem install flay reek` with
  the Ruby that runs asgard. Adding them to the project's Gemfile isn't
  enough unless asgard itself runs under that bundle. The other gates run
  their tool through the project's bundle or from `PATH`; when one is
  missing, most print a SKIP line that says how to install it.
- **Optional command-line tools**, needed only by the tasks listed:

  | Tool | Used by | Install |
  |------|---------|---------|
  | `gh` (authenticated) | `github_collect`; PR linkage in `branch_report` | `brew install gh`, then `gh auth login` |
  | `claude` | `weekly_report`, `shell_hourly` | Claude Code CLI, then `claude /login` once |
  | `icalBuddy` | `calendar_collect` | `brew install ical-buddy` |
  | `jira` | most `ticket` tasks | `brew install jira-cli`, then `jira init` |
  | `tbls`, `pg_isready` | `db_doc*` tasks | `brew install k1LoW/tap/tbls`; PostgreSQL client tools |
  | `psql`, `pg_dump`, `pg_restore`, `createdb`, `dropdb`, `pg_isready`, `pg_ctl` | `db` tasks | PostgreSQL client tools, e.g. `brew install postgresql` |
  | `aws` (CLI v2) | `aws` tasks | `brew install awscli` |
  | `docker` | `fake_aws` tasks | Docker Desktop, or any Docker engine |
  | `mkdocs` | `doc` tasks in a MkDocs repo | `asgard doc install` (Homebrew) |
  | `typos` | `typos_check`, `typos_fix` | `brew install typos-cli` |
  | `archspec` | `archspec_check` (also needs an `Archspec.rb`) | `gem install archspec`, then `archspec init` |
  | `exhale` | `exhale_check` (advisory) | `gem install exhale` |

- **macOS assumptions.** `doc open` and `db_doc_open` call macOS `open`,
  `doc install` installs mkdocs with Homebrew, and `calendar_collect` reads
  macOS Calendar through icalBuddy.

## Contents

| File | Provides |
|------|----------|
| `.loki` | Imports every top-level `*.loki` file below (not `rails/` or `client/`), for `import_up "dev/.loki"` |
| `gem_tasks.loki` | Gem lifecycle: `console`, `build`, `install`, `release` |
| `quality.loki` | The `quality` gate and the `*_check` tasks it runs (`quality/` holds its RSpec progress listener) |
| `rails/quality_rails.loki` | Rails-only checks: Brakeman, RailsBestPractices, ActiveRecordDoctor |
| `git.loki` | Per-repo git basics: `push`, `pull` (ff-only), `fetch` |
| `doc_tasks.loki` | Documentation site tasks, for a repo with `mkdocs.yml` or `bridgetown.config.yml`: `doc install`, `doc build`, `doc serve`, `doc open` |
| `client/status_report.loki` | End-of-week client status reporting: `daily_summary`, `weekly_report`, `shell_hourly` |
| `client/ticket.loki` | Jira tickets from the command line: `asgard ticket show`, `mine`, `search`, `ffind`, `move`, `comment`, `history`, `ready`, `children`, `remaining`, `link`, `attach`, `detach`, `create`, `sync`, `branch`, `pr`, and more |
| `iterm_tasks.loki` | Terminal fixes: `half_duplex_screen_fix`, `clear_scroll_back_buffer` |
| `branch_report.loki` | `branch_report [DAYS]`: read-only Markdown report with one row per branch (local and origin copies together), sorted into Active, Stale (idle over DAYS, default 30) and Merged. Uses `gh`, when available, to recognize squash- and rebase-merged PRs |
| `rails/db.loki` | Local PostgreSQL development database: `asgard db status`, `tables`, `psql`, `backup`, `backups`, `dumps`, `restore`, `diff`, `start`, `stop` |
| `rails/db_doc.loki` | [tbls](https://github.com/k1LoW/tbls) schema docs into `notes/dbdoc` (needs Postgres up on localhost:5432; `DB_DOC_DSN` overrides the default vbr_development DSN): `db_doc`, `db_doc_diff`, `db_doc_mermaid`, `db_doc_open`, `db_doc_clean` |
| `rails/dev.loki` | Background dev stack for a Rails app: `asgard dev up`, `down`, `status` (`bin/dev`, plus Mailpit when installed) |
| `runbook.loki` | Operational runbooks in `docs/runbooks` (or `RUNBOOKS_DIR`): `asgard runbook list`, `asgard runbook show NAME` |
| `aws.loki` | AWS SSO sign-in: `asgard aws login`, `logout`, `whoami`, `profiles`, `portal` |
| `fake_aws.loki` | AWS's local API emulator in Docker (its Dockerfile and smoke test are in `fake_aws/`): `asgard fake_aws build`, `start`, `stop`, `restart`, `status`, `logs`, `version`, `exports`, `smoke`, `remove` |
| `rubocop-strict.yml` | Cops kept enabled with no exclusions over `.rubocop_todo.yml` (when inherited after it; see below) |

### gem_tasks.loki

Universal gem lifecycle tasks. Uses the `gem` command directly — no rake
dependency. `@@gem_name` defaults to the gemspec's basename (falling back to
the directory name); a repo may set it earlier if it differs. A `gem_version`
helper takes the version from the gemspec, falling back to a string `VERSION`
in `lib/<gem_name>/version.rb` (dashes become slashes), then in the first
`lib/**/version.rb` that defines it. It imports `quality.loki` itself, since
`build` runs the gate, so it can be imported alone.

- `build` — runs the `quality` gate, then builds the gemspec into
  `pkg/<name>-<version>.gem`; aborts if no version can be determined
- `install` — builds, then `gem install --local`
- `release` — refuses to run on any branch but `main` (set
  `@@release_branch` earlier for another), before the gate or the build
  start; then builds, aborts if no version can be determined, confirms
  (skip with `-y`), requires a clean working tree and an unused
  `v<version>` tag, then tags, pushes, and `gem push`es to RubyGems

### quality.loki

The heart of the shared layer. `quality` discovers every task whose name ends
in `_check` at run time — from this file, from `rails/quality_rails.loki`, or from a
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

**Which directories are scanned.** Flog, Flay, Reek and Fasterer look at
the directories in `@@quality_dirs`, `lib` by default. A repo whose source
lives elsewhere (a Rails app's `app/`) sets it in its own `.loki`, inside
`class Tasks` (a class variable can't be assigned at the top level of a
`.loki`):

```ruby
class Tasks
  @@quality_dirs = %w[app lib].freeze
end
```

Directories that don't exist are left out; when none of them exists, those
four gates report SKIP with a hint to set `@@quality_dirs`.

Reek fails only on files that are new to, or worse than, the per-file smell
counts grandfathered in `.quality/reek_baseline.txt`. Its companion task,
`reek_baseline`, regenerates that file from the current smells: run
`asgard reek_baseline` when a regression is intentional (or to ratchet the
counts down after a cleanup).

**Live board.** On a terminal, with the `tty-spinner` gem installed for
asgard's Ruby (`gem install tty-spinner`), `quality` draws one spinner row
per gate and each gate settles its row with a badge and a one-line note as
it finishes. Off a terminal (CI, a pipe) or without the gem, each gate
prints a `Label: note` line and the summary lists every gate, as before.

**test_check picks its runner.** `bundle exec rake test` by default;
`bundle exec rspec` when the repo has `spec/` and bundles `rspec-core`;
`bundle exec parallel_rspec` when it also bundles `parallel_tests`. Both
RSpec runs set `COVERAGE=true`. The parallel run uses
`PARALLEL_TEST_PROCESSORS` processes (default: CPU count, at most 8, never
more than there are spec files) and, on the live board, shows a progress
bar fed by `quality/test_progress_listener.rb`, which is loaded through
`SPEC_OPTS` (appended to any `SPEC_OPTS` you set) so the app carries no
code for it. A Rails app needs its
per-process test databases first: `bin/rails parallel:prepare`.

**A gate that raises is a FAIL, not a crash.** An exception out of any
`*_check` task is written with its backtrace to that gate's `*_output.txt`
and the gate reports FAIL, so the other gates' results and the summary
still print. `GATE_CRASH_STATUS` in `quality.loki` sets that status.

**Project Ruby.** When the repo has a `.ruby-version` and rbenv has that
version, `bundle exec` gates run on it rather than on asgard's Ruby, which
would otherwise fail on bundler's Ruby version check.

**Writing a gate.** A new `*_check` task reports through the helpers here
instead of printing: `run_gate(name, label, command, summary:)` runs a
command, saves its output and settles the row; `report_gate` does the same
for output the task produced itself; `skip_gate(name, label, reason)`
reports SKIP. A gate that calls `puts` breaks the live board's layout.

### rails/quality_rails.loki

Rails-specific `*_check` gates, gated on `RAILS_ROOT` (set in a Rails repo's
`.envrc`) rather than `defined?(Rails)`, since Asgard runs outside the app's
process. Once imported, its checks are picked up by `quality` automatically.

ActiveRecordDoctor is advisory: its findings report WARN, never FAIL. Its
task is `ard_check` (it was `active_record_doctor_check`) and its output
goes to `ard_output.txt`.

### client/status_report.loki

Personal end-of-week client status reporting. `daily_summary` discovers
every `*_collect` task the same way `quality` discovers `*_check` tasks,
runs them, and writes the day's activity to `notes/_status/<date>.md`
under `RR`. `weekly_report` reads Mon–Fri's daily files and pipes them
through headless Claude Code (`claude -p`) to produce a client-facing
Markdown report at `notes/_status/week-of-<monday>.md`.

Each collector is best-effort and never fails the run — a missing tool or
unset env var just prints a SKIP line instead of aborting the others:

- `notes_collect` — `_notes.txt` journal entries (no config needed)
- `git_collect` — `git log --all` (every branch, not only the one checked
  out), scoped to `git config user.email`
- `github_collect` — needs `gh` authenticated (`gh auth status`)
- `jira_collect` — needs `JIRA_SITE`, `JIRA_PROJECT`, `JIRA_USER_EMAIL`,
  `JIRA_API_KEY`
- `claude_sessions_collect` — reads `~/.claude/projects/<repo>/*.jsonl`
- `shell_history_collect` — the day's `shell_hourly` summaries when there
  are any, otherwise the day's commands from `~/.bash_history`. Only
  commands bash saved with a timestamp are found, so set `HISTTIMEFORMAT`
  in your shell profile
- `calendar_collect` — needs `icalBuddy` (`brew install ical-buddy`)

Add a source by defining another `*_collect` task; nothing else needs to
be redeclared.

`git_collect` and `github_collect` cover the repo at `RR` by default. For a
project whose work is spread over several clones, list the others in
`STATUS_REPO_DIRS`, separated by `:` (relative paths are resolved against
`RR`); each repo then gets its own heading in the day's file (its directory
name, or `parent/name` when two repos share a name):

```bash
export STATUS_REPO_DIRS="branches/working:../shared-library"
```

`shell_hourly` summarizes the clock hour that just ended: it sends that
hour's shell commands to `claude -p` and writes a one-to-three sentence
summary to `notes/_status/shell/<date>/<HH>00-<HH+1>00.md`. Lines that look
like a secret assignment (`_KEY=`, `_TOKEN=`, `_SECRET=`, `PASSWORD=`) are
left out before anything is sent. It is meant to be scheduled from the
project's `.loki`:

```ruby
schedule :shell_hourly, at: %w[10:00 11:00 12:00 13:00 14:00 15:00 16:00 17:00], on: :weekdays
```

`STATUS_DATE=2026-09-29 STATUS_HOUR=14 asgard shell_hourly` redoes one hour.

### client/ticket.loki

Jira from the command line, under `asgard ticket`. A ticket is named by its
full key (`PROJ-175`, `proj-175`) or just its number (`175`), which gets
`JIRA_PROJECT` as its prefix.

- **Read**: `show KEY`, `comments KEY`, `history KEY`, `transitions KEY`,
  `children EPIC`, `browser KEY` (alias `open`)
- **Find**: `mine` (your open tickets), `search JQL` (alias `jql`),
  `ffind [QUERY...]` (fuzzy match on key, title, status, assignee and
  label), `remaining KEY` (a status table of KEY and every ticket created
  after it; `--markdown` for a Markdown table)
- **Change**: `move KEY TRANSITION` (by partial name, target status or id),
  `comment KEY TEXT`, `ready KEY` (assignee, `--due`, `--estimate`),
  `link A VERB B`, `attach KEY FILE...`, `detach KEY [NAME...]`,
  `create TYPE SUMMARY`
- **GitHub**: `pr KEY` lists the PRs whose title or branch names the ticket
- **Work**: `branch KEY [FROM]` starts a branch named for the ticket, from
  the parent epic's branch when there is one, else the base branch; it
  refuses a Done or Canceled ticket unless `--force`
- **Mirror**: `sync` keeps a directory of `KEY.json`, `KEY.md` and
  `KEY.html` files current for the tickets changed since the last sync,
  with done tickets in a `_done` subdirectory (`--since`, `--dry-run`).
  It runs two commands of yours: one that fetches tickets by key, one
  that renders the Markdown as HTML

`detach` deletes attachments, which Jira cannot restore; with no name it
only lists them.

It needs [jira-cli](https://github.com/ankitpokhrel/jira-cli) set up with
`jira init`, and these variables, usually from the project's `.envrc`:

| Variable | Meaning |
|----------|---------|
| `JIRA_SITE` | The site URL, including `https://` |
| `JIRA_USER_EMAIL` | Your Atlassian account's email |
| `JIRA_API_KEY` | An Atlassian API token, used for the REST calls |
| `JIRA_API_TOKEN` | The same token, under the name jira-cli reads |
| `JIRA_PROJECT` | The project key, e.g. `PROJ` |
| `JIRA_OPEN_COMMAND` | Optional: the browser command `--chrome` runs |
| `JIRA_ACCEPTOR_FIELD` | Optional: the id of an "Acceptor" user custom field, which turns on `ready --acceptor` |
| `JIRA_GITHUB_REPO` | Optional: `OWNER/REPO` for `pr`; default is the repo in the current directory |
| `JIRA_SYNC_DIR` | Optional: the `sync` mirror directory; default `notes/jira` under `RR`, else the current directory |
| `JIRA_SYNC_FETCH_COMMAND` | Optional: run in the mirror directory with the changed keys, it writes `KEY.json` and `KEY.md`; default `~/scripts/jira_get.rb` |
| `JIRA_SYNC_RENDER_COMMAND` | Optional: run there with the `KEY.md` files, it writes `KEY.html`; default `~/scripts/md2html -o %{dir}`; an empty string skips rendering |
| `JIRA_SYNC_DONE_STATUSES` | Optional: comma-separated statuses whose tickets move to the done subdirectory; default `Done` |
| `JIRA_SYNC_DONE_DIR` | Optional: that subdirectory's name; default `_done` |
| `JIRA_BRANCH_COMMAND` | Optional: what `branch` runs, with the new branch and its source appended; default `git switch -c` |
| `JIRA_BRANCH_BASE` | Optional: the source for a ticket with no parent epic branch; default `main` |
| `JIRA_BRANCHES_DIR` | Optional: for a project with one clone per branch, the directory of clones; the parent epic's branch exists when its clone does |

`sync` is not scheduled here. A project that wants it hourly declares
`schedule :ticket, options: "sync", as: "ticket_sync", at: %w[09:15 13:15 17:00]`
in its own `.loki`.

The file's header explains which tasks go through jira-cli and which
through the REST API, and why.

### aws.loki

AWS IAM Identity Center (SSO) sign-in, under `asgard aws`:

- `login`: `aws sso login` for the SSO session, so one sign-in covers
  every profile that shares it; with `--profile NAME` it signs in through
  that profile instead
- `logout`: ends the SSO session and clears the cached credentials
- `whoami` (alias `id`): the account and ARN the profile resolves to, and
  when the SSO token expires
- `profiles`: each profile in the config file with its account, role and
  SSO session
- `portal`: opens the SSO start page in the browser; `NO_OPEN=1` prints
  the URL instead

Every task takes `--profile NAME` (default `AWS_PROFILE`, else `default`)
and `--sso-session NAME`. The session defaults to `AWS_SSO_SESSION`, else
the one the profile names, else the config file's only `[sso-session]`
section. The config file is `AWS_CONFIG_FILE`, else `~/.aws/config`.

A project adds its own AWS tasks to the same group by reopening
`AwsCommands` in its `.loki` after importing this file; `aws_json`
(run an `aws` command and parse its JSON, with a hint when it fails) is
there to build on. One thing to know when doing so: a `helper` block runs
on the class, so it cannot read the running task's `options`. Code that
needs them goes in a method inside `no_commands do ... end`.

### branch_report.loki

`asgard branch_report [DAYS]` prints a Markdown report of every branch
except the default one. A branch and its `origin/` copy share a row, and
when both exist the newer tip is the one measured. Each row lands in one
bucket:

- **Active**: an open PR, or a commit within DAYS (default 30)
- **Stale**: unmerged, no open PR, idle for over DAYS
- **Merged**: the tip is in `origin/<default>` as of the last fetch, or a
  PR from the branch was merged and the branch has not moved since

The PR check needs `gh` authenticated for the repo, and is what recognizes
squash and rebase merges; without `gh` the report says so and uses git
ancestry alone. A long-lived branch such as `develop` counts as merged
only until it gets its next commit. The task never fetches, deletes or
pushes; run `git fetch --prune` first for current data.

A branch with no PR of its own can be matched to one by ticket id: set
`BRANCH_TICKET_PATTERN` to a regular expression such as `PROJ-\d+`, or
`JIRA_PROJECT`, from which `<JIRA_PROJECT>-<number>` is built.

### runbook.loki

A discovery layer over a repo's operational runbooks, the Markdown files
in `docs/runbooks` (`README.md` is left out). `asgard runbook list` prints
each file's name and its first heading; `asgard runbook show NAME` opens
the one whose name contains NAME (case-insensitive, `-` and `_` treated
alike, a trailing `.md` ignored; an exact name wins) in `glow` when
installed, else `$PAGER`, else `less`. Off a terminal
it prints the file instead. Set `RUNBOOKS_DIR` when the runbooks live
somewhere else.

### rails/db.loki

Tasks for a Rails app's local PostgreSQL development database, under
`asgard db`:

- `status`: whether the server answers, the size and connection count of
  each of the app's databases, and the latest applied migration
- `tables`: the 20 largest tables, with live row counts
- `psql`: a psql session on the database
- `backup` (alias `dump`): a `pg_dump -Fc` snapshot in the dump directory,
  named `DATABASE-YYYYMMDD-HHMMSS.dump`, mode 600
- `backups`: this database's snapshots; `dumps [DATABASE]` lists every
  database's, and `dumps --keep N` deletes all but each one's newest N
  (it asks first; `-y` skips the question)
- `restore [DUMP]`: replaces the database with a snapshot, by default its
  newest. This drops the database. It first backs the current one up
  (`--no-backup` skips that), prints what it will do, and asks you to type
  the database's name (`-y` skips the question). `--dry-run` stops after
  the checks. It prints the command that puts the previous database back
- `diff A.dump B.dump`: how the schema in B differs from A, as objects
  added, removed and changed; `--sql` prints the unified diff of the whole
  schema instead. It reads the two files only
- `start`, `stop`: `pg_ctl` on the cluster in `$PGDATA`

Settings come from the environment:

| Variable | Meaning | Default |
|----------|---------|---------|
| `DB_NAME` | The database | `<app directory>_development`, the app directory being `RR` or the current directory |
| `DB_HOST`, `DB_PORT` | The server | `localhost`, `5432` |
| `DB_USER` | The role | `PGUSER`, else your login name |
| `DB_PASSWORD` | The role's password, passed to the PostgreSQL tools as `PGPASSWORD` | none (`PGPASSWORD` or `~/.pgpass` also work) |
| `DB_DUMP_DIR` | Where dumps go | `tmp/db-dumps` in the app directory |
| `DB_TUNNEL_PORTS` | Comma-separated local ports that forward to a remote database | none |

The environment is the only configuration, so a project needs no file of
its own. One whose root is not the Rails app's directory exports
`DB_NAME`, since the default name would be taken from the wrong directory.

`restore` refuses to run unless the target is on this machine: the host
must be `localhost` or a socket directory, the port must not be in
`DB_TUNNEL_PORTS`, the database must not be a system one, and the server
itself must report a loopback or socket address. The last check catches a
tunnel to a remote server on a port that was not listed.

Keep the dump directory out of git: a dump is a full copy of the data.

### rails/dev.loki

`asgard dev up` (alias `start`) starts `bin/dev` in the background, with
its output appended to `log/development.log` and its pid in
`tmp/pids/dev_server.pid`. When Mailpit is installed it is started too
(or adopted, if already running) to catch the mail the app sends in
development. `asgard dev down` (alias `stop`) stops both, and
`asgard dev status` shows what is running. Run them from the app's root;
`DEV_SERVER_COMMAND` replaces `bin/dev`.

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
