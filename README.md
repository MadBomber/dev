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
| `iterm_tasks.loki` | Terminal fixes: `half_duplex_screen_fix`, `clear_scroll_back_buffer` |
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
