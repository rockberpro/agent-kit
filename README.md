# Agent KIT

Claude Code plugin that sets up an agent context on a new project: guards, the
`.agents/` structure, and the skills that map the repository into memory and rules.

The repository root is the plugin and also a one-entry marketplace, both called
`agent-kit`, so the plugin installs as `agent-kit@agent-kit`.

## Install

Register the marketplace — **once per machine**, not per project:

```bash
claude plugin marketplace add https://github.com/rockberpro/agent-kit.git
```

Install `agent-kit`. The default scope is `user`, which is what you want here: the
master-guard then applies to every repository of yours.

```bash
claude plugin install agent-kit@agent-kit
```

Inside Claude Code the same commands exist as `/plugin marketplace add`,
`/plugin install` and `/plugin` (interactive UI). After installing mid-session, run
`/reload-plugins`.

## Use it on a new project

```bash
cd /path/to/project
claude
```

and in the session:

```
/agent-kit:scaffold
```

The skill sets up `.agents/` (`memory/`, `rules/`, `settings.json`, `.claude` symlink),
the root `AGENTS.md` with `CLAUDE.md` pointing at it, and writes the anti-drift rule
`.agents/rules/memory.md`. It is idempotent: run again on an already initialized
project and it only creates what is missing, never overwriting content.

The structure starts empty on purpose. Two skills fill it, each one asking before it
writes:

```
/agent-kit:memory [area]   # maps the repo into AGENTS.md + .agents/memory/
/agent-kit:rules  [area]   # writes .agents/rules/: the commit policy, then per-area rules
```

Without an argument they do the full pass (for `memory`, the bootstrap phases, stopping
at a minimum usable catalog); with an area — a module, a directory, a subject — they map
only that one, which is how the catalog grows afterwards: by the tasks that touch it.

The `settings.json` it writes carries only the project's policy — no blind `git add` —
and never names this plugin. Whether commits and PRs keep agents (Claude, Codex, ...) as
co-authors is asked by `/agent-kit:rules` with the rest of the commit policy, in your
language, and written both to `rules/commit.md` and to `attribution` in `settings.json`. The guards act for whoever
has the plugin installed, so each teammate runs the *Install* steps once on their
machine; a clone without it still gets the deny list, just not the guards.

**Windows:** `.claude` and `CLAUDE.md` are symlinks. Turn on Developer Mode (Settings →
System → For developers) and clone with `git clone -c core.symlinks=true ...`; otherwise
git checks them out as small text files and the context is silently off. Already cloned?
`/agent-kit:scaffold` detects it and repairs the links.

## Update a project that already has the context

Nothing is re-created and nothing is replaced without a diff and a yes:

```
/agent-kit:update-all      # the four passes below, in order, one report
/agent-kit:update-hooks    # settings.json against the template, drops old guard copies
/agent-kit:update-memory   # index, globs, notes whose area changed since they were touched
/agent-kit:update-rules    # mandatory rules, dead globs, duplicates, new candidates
```

`update-all` runs the `scaffold` first (idempotent: it only adds the missing structure),
then hooks → memory → rules — rules last, because they point at notes. Guard copies that
older versions put in `.agents/hooks/` are removed on a yes: the plugin runs the guards now.

## Uninstall

```bash
claude plugin uninstall agent-kit@agent-kit
claude plugin marketplace remove agent-kit
```

## What is inside

All three guards are checks in one hook, `hooks/guard.sh`, run before every Bash call.

- **guard `master-guard`** — on `master`/`main`, blocks anything that writes a commit
  there (`commit`, `cherry-pick`, `revert`, `am`, `rebase`), plus `git merge`,
  `git reset --hard` and any `push` that targets the protected branch. `--abort` /
  `--continue` on a stuck sequencer still go through. Fails open: any internal error
  exits 0, never wedging the session. Test:
  `bash hooks/master-guard.test.sh`.
- **guard `secret-guard`** — blocks a `git commit` whose content looks like a secret:
  a private-key header, a well-known token format (AWS/GitHub/Slack/GCP), or a `.env`
  or keystore (`.p12`/`.pfx`/`.jks`) being added. It only checks added lines, so a
  secret already in history does not block new commits — keystores are matched by name
  instead, since a binary diff has no lines to scan. Also fails open. Test:
  `bash hooks/secret-guard.test.sh`.
- **guard `memory-drift-guard`** — blocks a `git commit` that touches code covered by a
  memory note (declared in the note's `paths:` frontmatter) when the note is not in the
  same commit, so it is reviewed while the diff is fresh. `SKIP_MEMORY_CHECK=1` in front
  of the command when the note still holds. A note without `paths:` is never demanded.
  Also fails open. Test: `bash hooks/memory-drift-guard.test.sh`.
- **rule template `templates/rules/memory.md`** — the always-on half of the same
  contract: read the area's note before editing, fix it in the same task when it goes
  wrong, stage it with the code. Whichever of `scaffold`, `memory` or `rules` meets a
  `.agents/memory/` without `.agents/rules/memory.md` copies it there, translated into
  the project's language; none overwrites an existing one.
- **skill `/agent-kit:scaffold`** — sets up `.agents/` (memory, rules, settings,
  `.claude` symlink) in a repository that does not have it yet.
- **skill `/agent-kit:memory [area]`** — the mapping procedure: cheap reconnaissance,
  non-negotiables into `AGENTS.md`, architecture, module map, domains, then the
  `MEMORY.md` index; with an area, deepens just that one. A system with several
  domains (business or technical) gets one domain note each (`kind: domain`) plus a
  `domains.md` map. Carries the criteria for what makes a note worth reading and where
  each fact goes (`AGENTS.md` / `rules/` / `memory/`).
- **skill `/agent-kit:rules [area]`** — path-scoped rules in `.agents/rules/`: asks the
  commit policy and writes the always-on `commit.md`, then one short imperative rule per
  area, globs checked against `git ls-files`. Every note that owns an area gets a
  mandatory read rule that orders reading it — a `kind: domain` note over the whole
  domain, any other note with `paths:` over those globs — so the agent reads it as soon
  as it opens a file there, not only when the commit guard catches it.
- **agent `agent-kit:explorer`** — read-only investigator: maps a new demand or the
  blast radius of a change, returns a report, never edits. The `memory` and
  `update-memory` skills fan out to it.
- **agent `agent-kit:planner`** — read-only: turns an explorer report into ordered
  steps, each with its files, the rule or note that constrains it, and its check.
- **agent `agent-kit:implementer`** — does one planned step: edits code and the stale
  note, runs the step's check, reports. Never stages or commits.
- **agent `agent-kit:test-runner`** — finds and runs the project's tests, returns only
  the failures and their cause. Never edits.
- **agent `agent-kit:reviewer`** — read-only: checks a diff against the project's own
  memory, rules and commit/PR policy, the part a generic review does not know.
- **skills `/agent-kit:update-{all,hooks,memory,rules}`** — review an existing context;
  see *Update a project* above.

## Publish

The marketplace is this repository; a release is a pushed tag (see *Versioning*).

**If the repository is private**, `marketplace add` clones without interaction and has
no way to ask for a password — either the repository is public/internal, or every
person needs a credential helper already configured
(`git config --global credential.helper store`, with an access token). If that
becomes friction, switch the URL to SSH
(`git@github.com:rockberpro/agent-kit.git`).

## Versioning

`version` in `.claude-plugin/plugin.json` is what decides whether a project
gets an update — without bumping it, every commit counts as a new version. Release
flow:

```bash
# 1. change the code
# 2. bump version in plugin.json (semver)
claude plugin validate . --strict && claude plugin validate .claude-plugin/plugin.json --strict
for t in hooks/*.test.sh; do bash "$t" || break; done
# when a skill changed: full memory + rules passes on the fixtures in evals/ (costs real runs)
claude plugin eval . --scaffold --allow-tools Bash Write Edit --runs 3
git commit -am "feat(agent-kit): <what changed>"
claude plugin tag agent-kit          # creates agent-kit--v0.11.0, checking that plugin.json
                                # and the marketplace.json entry agree
git push --follow-tags
```

There is no CI in this repository on purpose — the kit does not assume a forge. The
validate + self-check line above is the gate: skip it and a broken guard reaches every
machine on the next `marketplace update`. The guards and the self-checks need only `bash`, `git` and `perl`
(with its core `JSON::PP`), which Git for Windows bundles and every Linux git pulls in.

On each machine: `/plugin marketplace update` and restart the session.

**Pinning** (a machine that must not break) — register the marketplace at a tag:

```bash
claude plugin marketplace add https://github.com/rockberpro/agent-kit.git#agent-kit--v0.11.0
```

Without a ref it follows the default branch and picks up everything that lands there.

## Company mirror

A company that cannot depend on someone else's repository keeps its own copy and
decides when to take updates. Projects never name the marketplace, so nothing in them
changes — only where each machine gets the plugin from.

```bash
git clone https://github.com/rockberpro/agent-kit.git && cd agent-kit
git remote rename origin upstream
git remote add origin <company-git-url>
git push -u origin main --tags
```

Keep the marketplace and plugin names (`agent-kit`, `agent-kit@agent-kit`): the install
commands refer to them.

- **Machines:** `claude plugin marketplace add <company-git-url>` instead of the GitHub URL
  (already registered → `claude plugin marketplace remove agent-kit` first).
- **Taking an update:** `git fetch upstream --tags && git merge agent-kit--v<version>`,
  run the release gate above, then `git push origin main --tags`. The upstream tags
  come along, so `ref` pins keep working.

If a second plugin ever joins, move each one into its own directory and point its
`marketplace.json` entry there (`"source": "./<plugin>"`) — the catalog keeps its name,
so projects do not notice.

## Language

Everything in this repository is written in English — code, docs, hook output. What
the skills generate inside a target project follows **that project's** language: a
Portuguese codebase gets Portuguese notes, rules and `AGENTS.md` sections, the copied
`rules/memory.md` template included.

The language is declared once, not re-guessed on every run: the `scaffold` proposes it
from README, comments and `git log`, the user confirms, and it goes into `AGENTS.md` as
one line under *Memory Catalog*. `memory` and `rules` read it from there (and settle it
the same way if it is missing), and since `AGENTS.md` loads in every session, a note
fixed outside any skill lands in the same language. Filenames stay in English — the
skills find `rules/memory.md`, `rules/commit.md` and `MEMORY.md` by name.

## What does not belong here

Two things stay in the repository's own `.agents/`:

- **a script that serves only one project** — reading a specific `.ini`, a homegrown
  linter. It becomes a plugin when a second project needs it.
- **a convention** — the commit standard, the target runtime, the encoding; the rules and notes the `memory`/`rules` skills write. That is
  information about the repo; it has to be readable by whoever clones it without this
  marketplace installed. The skills carry the *procedure*; the project keeps the
  *result*. Nothing here ships a pre-filled note or rule for a project to inherit — an
  inherited convention that is wrong is worse than none, because nobody suspects it.
  The one exception is `templates/rules/memory.md`, which states how the catalog is
  kept, not a fact about any project.
