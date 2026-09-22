---
name: scaffold
description: Creates the .agents/ structure (memory, rules, settings, guards, .claude symlink) in a project that does not have it yet, then hands off to the memory and rules skills. Use when the user asks to initialize/configure the agents directory, the memory base or the .agents of a new repository.
---

# scaffold

Sets up a project's `.agents/` skeleton. **Idempotent**: run again on an already
initialized project and it only creates what is missing, touching nothing that exists.

## Language of what you write

This skill is written in English; what it *generates* in `.agents/` and `AGENTS.md` is
written in the project's language, and so is everything the `memory` and `rules` skills
write later — notes, index, rules, headings, the "back to the index" line.

That language is a project fact, so it is **declared, not re-guessed** on every run:

1. `AGENTS.md` already declares it (the line under *Memory Catalog*, see step 4) → use it.
2. Otherwise, propose one from the evidence — README, code comments, `git log` subjects —
   and **confirm with the user** before writing anything. Code identifiers in English do
   not make the project English: the team's prose (docs, comments, commit messages)
   decides. Evidence split or absent → ask, do not default.
3. Record the answer in step 4. Any later session — with or without these skills — then
   writes notes and rules in it, because `AGENTS.md` loads every time.

Filenames, keys and paths stay as specified here regardless (English kebab-case): the
skills find `rules/memory.md`, `rules/commit.md` and `memory/MEMORY.md` by name.

## Convention

Everything lives in `.agents/` (tool-neutral) and `.claude` is a symlink to it so
Claude Code sees it. That way other agent CLIs reuse the same directory. Same idea at
the root: the instructions file is `AGENTS.md` and `CLAUDE.md` is a symlink to it.

```
.agents/
  memory/            → note graph, one note per domain, MEMORY.md index (memory skill)
  rules/             → path-scoped instructions the harness injects (rules skill)
  settings.json      → permissions + team marketplace + repo hooks
  agents/            → project subagents (optional)
  skills/            → project skills (optional)
  hooks/             → this repository's hooks (the guards go here)
  .gitignore
.claude -> .agents
AGENTS.md
CLAUDE.md -> AGENTS.md
```

## Steps

1. **Survey what already exists** before writing anything. Every step below is
   conditional: what is already there stays as it is (do not overwrite, do not "fix"
   content), what is missing you create. At the end, report created vs. already
   existed.

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ls -ld .agents .claude AGENTS.md CLAUDE.md .agents/settings.json .agents/rules \
          .agents/rules/memory.md .agents/hooks/{master,secret,memory-drift}-guard.sh \
          .agents/memory/MEMORY.md 2>&1
   ```

   Two exceptions where you *do* adjust what exists, because it is structure and not
   content:

   - `CLAUDE.md` is a regular file and `AGENTS.md` does not exist → rename it
     (`git mv CLAUDE.md AGENTS.md`) and create the symlink. Content is preserved.
   - `.agents/settings.json` exists but is missing a guard in the `hooks` block, a
     `deny` entry or the plugin → step 3 adds what is missing, preserving the rest.

2. Create whatever structure is missing:

   ```bash
   mkdir -p .agents/memory .agents/rules .agents/hooks
   [ -e .agents/.gitignore ] || printf 'settings.local.json\n.obsidian\n' > .agents/.gitignore
   # A dangling symlink is invisible to -e but still occupies the name, so ln fails.
   if [ -L .claude ] && [ ! -e .claude ]; then rm .claude; fi
   [ -e .claude ] || ln -s .agents .claude
   ```

   With `memory/` comes its anti-drift rule — the always-on instruction to fix a note in
   the same task that made it wrong, which `memory-drift-guard` then enforces at commit:

   ```bash
   [ -e .agents/rules/memory.md ] || cp "${CLAUDE_PLUGIN_ROOT}/templates/rules/memory.md" .agents/rules/memory.md
   ```

   Freshly copied, translate it into the project's language (keep the filename).

3. **Guards and `.agents/settings.json`** — one script does both, the same one
   `/agent-kit:update-hooks` uses, so there is a single copy of the settings template:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-hooks.sh" --apply
   git add .agents/settings.json .agents/hooks/{master,secret,memory-drift}-guard.sh   # exec bit goes into git
   ```

   `--apply` only creates: the three guard copies (`master-guard`, `secret-guard`,
   `memory-drift-guard`) that are missing, a `settings.json` from the template when there
   is none, and — in an existing one — only the missing pieces: the marketplace and
   `agent-kit@agent-kit`, the `deny` entries for blind `git add`, the guard registrations.
   Everything else in it stays. A copy that differs from the plugin's is reported
   `outdated` and left alone — replacing it is `/agent-kit:update-hooks`, which shows the
   diff first. A symlinked copy is reported `linked` and never written through. Exit 1
   only means such lines are left; exit 2 (invalid `settings.json`) stops the scaffold —
   report it, do not hand-edit around it.

   The copies make the guards work in a clone with no marketplace, no trust prompt and no
   session restart; whoever clones is still offered the plugin when trusting the folder.
   If the plugin is also enabled, each guard runs twice — harmless, both block the same
   thing. The `deny` list stops a stray `.env` or real config from being staged at all;
   `secret-guard` is the net behind it.

4. **`AGENTS.md` at the root, with `CLAUDE.md` as a symlink to it.** The real file is
   `AGENTS.md` (a convention other CLIs also read); Claude Code sees it through the
   symlink.

   ```bash
   if [ -L CLAUDE.md ] && [ ! -e CLAUDE.md ]; then rm CLAUDE.md; fi   # dangling: drop it
   [ -e AGENTS.md ] || [ -L CLAUDE.md ] || [ ! -e CLAUDE.md ] || git mv CLAUDE.md AGENTS.md
   [ -e AGENTS.md ] || touch AGENTS.md          # then write the content below
   [ -e CLAUDE.md ] || ln -s AGENTS.md CLAUDE.md
   ```

   If `AGENTS.md` does not mention the memory yet, append this (leaving the rest
   alone), in the project's language:

   ```markdown
   ## Memory Catalog

   Persistent instructions live in `./.agents/memory/`. Index:
   [.agents/memory/MEMORY.md](.agents/memory/MEMORY.md). Before any action in a
   domain, read the matching file — the rules live there, not here.

   Notes and rules under `.agents/` are written in <language> (`<tag>`).
   ```

   If the section exists but has no language line, add just that line to it. Example
   for a Portuguese project: `Notas e regras em .agents/ são escritas em português
   (pt-BR).`

5. Report what you created (created vs. already existed, plus any `outdated`, `linked`
   or `legacy` line the script printed — those are `/agent-kit:update-hooks`), and say
   the plugin only activates after `/plugin marketplace update` + a session restart.

6. **Hand off to the mapping skills.** The structure is empty until they run; both
   read a lot and ask before writing, so offer them instead of starting unasked:

   - `/agent-kit:memory` — no `MEMORY.md` yet: maps the repository into `AGENTS.md`
     and the catalog (phases 0–4, then stops).
   - `/agent-kit:rules` — no `rules/commit.md` yet: asks the commit policy and writes
     it, then the path-scoped rules for the candidates the memory pass found.

   If the user already asked for the whole setup in one go, run them in that order.

## What this skill does NOT do

Anything specific to a single project (a homegrown database client, a homegrown
linter) stays in that repository's own `.agents/hooks/` and `.agents/skills/`. Only
what has already served more than one project becomes a marketplace plugin.
