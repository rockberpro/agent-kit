---
name: scaffold
description: Creates the .agents/ structure (memory, rules, settings, .claude symlink) in a project that does not have it yet, then hands off to the memory and rules skills. Use when the user asks to initialize/configure the agents directory, the memory base or the .agents of a new repository.
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
  settings.json      → permissions + team marketplace (enables the guards)
  agents/            → project subagents (optional)
  skills/            → project skills (optional)
  hooks/             → this repository's own hooks (optional)
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
          .agents/rules/memory.md .agents/memory/MEMORY.md 2>&1
   ```

   Two exceptions where you *do* adjust what exists, because it is structure and not
   content:

   - `CLAUDE.md` is a regular file and `AGENTS.md` does not exist → rename it
     (`git mv CLAUDE.md AGENTS.md`) and create the symlink. Content is preserved.
   - `.agents/settings.json` exists but is missing a `deny` entry or the plugin → step 3
     adds what is missing, preserving the rest.

2. Create whatever structure is missing:

   ```bash
   mkdir -p .agents/memory .agents/rules
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

3. **`.agents/settings.json`** — enables the plugin for whoever clones and denies blind
   `git add`:

   ```bash
   [ -e .agents/settings.json ] || cp "${CLAUDE_PLUGIN_ROOT}/templates/settings.json" .agents/settings.json
   ```

   An existing one gets only what it lacks from the template — the `agent-kit`
   marketplace, `agent-kit@agent-kit` in `enabledPlugins`, each `deny` entry — and
   everything else in it stays. Not valid JSON → report it and stop; do not hand-edit
   around it.

   The guards (`master-guard`, `secret-guard`, `memory-drift-guard`) run from the plugin,
   so they act wherever it is enabled; whoever clones is offered it when trusting the
   folder. The `deny` list stops a stray `.env` or real config from being staged at all;
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

5. Report what you created (created vs. already existed), and say the plugin only
   activates after `/plugin marketplace update` + a session restart.

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
