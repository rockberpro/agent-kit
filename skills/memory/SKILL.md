---
name: memory
description: Maps a repository into the .agents/memory/ knowledge catalog - fills the root AGENTS.md with the non-negotiables, writes architecture/domain/module notes and the MEMORY.md index. Use when the user asks to map, build, extend or refresh the project's memory, when .agents/memory/MEMORY.md does not exist, or when the area a task touches has no note. Pass an area (a module, directory or subject) to map just that one.
argument-hint: "[area]"
---

# memory

Builds and extends the project's knowledge catalog. Mapping is reading — do not ask
permission to read. **Ask before writing**, saying how many notes and which: the user may
want a smaller cut.

## Arguments

- **No argument** — full bootstrap: phases 0–4 below, then phase 6. If the catalog
  already exists, run only the phases whose output is missing; checking the notes that
  exist against the code is `/agent-kit:update-memory`.
- **An area** (`$ARGUMENTS`: a module, directory or subject) — phase 5 for that area
  only, then phase 6 to hook the note into the index. Read `MEMORY.md` first: if a note
  already covers the area, deepen that one instead of creating a sibling.

Run `/agent-kit:scaffold` first if `.agents/` does not exist. Settle the language
(next section) before anything else.

**Before writing the first note**, make sure the anti-drift rule exists — a catalog
without it rots silently between commits:

```bash
[ -e .agents/rules/memory.md ] || { mkdir -p .agents/rules && cp "${CLAUDE_PLUGIN_ROOT}/templates/rules/memory.md" .agents/rules/memory.md; }
```

Freshly copied, translate it into the project's language (keep the filename). Never
overwrite an existing one.

## Language of what you write

The language of `.agents/` is a project fact, declared once in the root `AGENTS.md` (the
line under *Memory Catalog* naming it, with a tag such as `pt-BR`) — read it from there,
do not re-guess it. If `AGENTS.md` does not declare it yet, settle it the way
`/agent-kit:scaffold` does (propose from README, code comments and `git log` subjects,
**confirm with the user**, add the line) before writing anything.

Every note, the index, the "back to the index" line and the `AGENTS.md` sections go in
that language. The exception is the glossary's *terms*: they follow the language **the
code** names things in (a table called `titulo` is `titulo` in an English catalog too) —
translating them introduces ambiguity. Filenames stay in English kebab-case.

An existing note in another language is a finding, not something to rewrite on the
side: list it in the report and offer to translate it.

## Three destinations: `AGENTS.md`, `rules/`, `memory/`

Know where a fact goes before writing it. The most common mistake is writing everything
into a note; the second is writing everything into `AGENTS.md`.

| Destination | Loaded | What goes there |
|---|---|---|
| root `AGENTS.md` | **every** session | this project's facts, in few lines: target runtime, encoding, commands, what CI really runs |
| `.agents/rules/` | when a file matching the rule's `paths:` is read | what to **obey** when editing that area — imperative, short (the `rules` skill writes these) |
| `.agents/memory/` | when the agent decides to open the note | what to **understand** to decide — the why, the measurements, the traps already paid for |

Rule and note differ in form, not subject: the same area yields a twenty-line rule and a
two-hundred-line note. The rule ends pointing at the note.

Inflating `AGENTS.md` is the most expensive mistake of the catalog: it is paid in every
session, not when useful. It points at where knowledge lives instead of holding it.

## What makes a note worth reading

These matter more than the order of the phases. A bad note costs more than no note — it
is read, believed, and wrong.

- **Document the why, not the what.** Class names, directory layout and signatures are
  found by reading the code in seconds. What becomes a note needs historical or business
  context: why that exception exists, what that odd name means, which rule the code obeys.
- **Inclusion test:** it took time to find out, or it led someone into a mistake. A
  measured trap is worth ten paragraphs of description.
- **No code copies, no line numbers.** They rot in weeks. Cite file paths and symbol
  names, which survive refactors.
- **Do not speculate.** Unconfirmed goes in as explicit uncertainty ("unconfirmed: X
  looks like Y"). Fabricated confidence is the most expensive defect of a catalog.
- **Write for someone with zero context who will act tomorrow.**
- **A note that does not fit in one read is two notes.**

## Phase 0 — Cheap reconnaissance

Before opening application code, take what metadata already gives. It answers half the
questions at a fraction of the cost.

- `README`, `docs/`, `CONTRIBUTING`, ADRs — read them, treat them as possibly stale.
- **Dependency manifest** (`package.json`, `composer.json`, `go.mod`, `pom.xml`,
  `pyproject.toml`, `Gemfile`...): stack, target runtime and — most valuable — libraries
  that give the domain away. A payment gateway client, an invoicing SDK, an ERP
  connector: each is a piece of the business showing.
- **CI config**, whatever the format: what is really a gate. Often much less than the
  README promises.
- `.editorconfig`, `.gitattributes`: encoding, line endings, indentation.
- **Repository shape:** directories two levels deep and where the mass of files is. The
  fattest directory is rarely the most important, but the most important is almost
  always one of the three biggest.
- **History:** `git log --format='%s'` over the last few hundred commits gives the real
  message convention; `git shortlog -sn` and `git log --name-only` show who touches what
  and which areas are alive. Areas with no commit in years are dead-code suspects — note
  the suspicion, do not conclude.
- **Database:** the schema is the best single source of business vocabulary — table and
  column names are the domain glossary written by the developers themselves. Use a
  read-only introspection skill if the project has one. If it does not, building one is
  **writing** and project-specific (which config holds the active connection is a project
  fact — guessing it connects to the wrong database silently): propose it, confirm the
  config with the user, and keep it in `.agents/skills/`.

## Phase 1 — Non-negotiables → root `AGENTS.md`

What an agent must know to **not break anything** on its first edit. This comes before
architecture on purpose: it is the phase that prevents damage. Survey, and write there:

- **Real source encoding**, checked on a sample, not assumed.
- **Target runtime version, and whether the local runtime matches.** When they differ,
  local validation lies both ways — accepts what breaks in production and rejects what
  works. Record *how* to validate against the right version.
- **Commands:** build, lint, test, format. And, separately, which of them CI really runs
  — the gap between the two is one of the most useful facts in the catalog.
- **Is there a real test suite?** A `test/` directory full of ad-hoc scripts is not
  coverage. No net is itself a non-negotiable: it changes how every change must be made.
- **Age and idioms of the code.** Legacy means imitate the surroundings, not modernize.
  Record the concrete idioms to imitate.
- **Tool traps** found along the way (a search that drops results, a check that passes
  on a corrupted file). Nobody rediscovers these for free.
- **Commits:** the convention `git log` actually shows (prefix, ticket reference), in one
  line.

`AGENTS.md` shape (headings in the project's language; keep the memory section the
scaffold wrote):

```markdown
# <Project> — Agent Guide

<One sentence: what the system is, for whom, on which stack.>

## Memory Catalog
<the pointer to .agents/memory/MEMORY.md, and the language line>

## Non-negotiables
- <target runtime, encoding, the no-test-net warning — a few bullets>

## Commands
<lint, test, build — and which one CI really runs>

## Architecture
<entry points, routing, layers — a few lines; the detail is in architecture.md>
```

What does not belong in `AGENTS.md` goes down to one of two places: **an editing
constraint becomes a rule**, **an explanation becomes a note**. Note the rule candidates
for the report at the end — the `rules` skill writes them.

## Phase 2 — Architecture and entry points → `architecture.md`

- **Every entry point**, not just the main one: HTTP, CLI, cron/scheduled jobs, queue
  workers, separate APIs/webservices, batch scripts at the root. A forgotten entry point
  is a whole class of invisible bugs.
- **One request's life, end to end, once and concretely** — from bootstrap to response.
- **Routing: how a URL or action becomes code.** If resolution is dynamic (a string
  built at runtime, naming convention, reflection), **this is the most valuable note in
  the whole catalog** — it is what makes a textual search for callers fail silently.
  Record the route format and where route strings live.
- **Authentication and authorization:** where they are checked, and whether a cache can
  mask a permission change.
- **Layers** and the contract between them; where the database connection is born; how
  configuration is loaded and what is kept out of version control.

## Phase 3 — Module map → skeleton of the `module-*.md` notes

Enumerate modules crossing three sources, because none alone is complete: the directory
structure, the application's routes/menu, and the permission table or equivalent if
there is one.

For each module, **one line only** in this phase: what it does in business terms (not
code terms), relative weight, and whom it talks to. Resist going deeper — you do not yet
know enough to know what matters.

## Phase 4 — Business domain → `domains.md`

The most valuable phase and the one the code gives least on its own. Without it the
agent knows where to change and not what it is changing.

- **Find the entity that crosses the whole system** and follow its life cycle end to
  end, naming each transition and the module that owns it. Almost every business system
  has one: the object born in one module that changes state along the flow and ends in
  another.
- **Glossary in the language of the code.** Table and column names are the best source.
- **User profiles:** who operates each module, and what each one can see.
- **Ask the user what the code cannot say.** A rule that exists by institutional
  decision, legal deadline, regulator obligation, contract, or "it is like this because
  X happened in 2014". No amount of reading recovers that, and it is exactly what causes
  rework when the agent assumes wrong. List the questions and ask them in one go.

**More than one business domain** (billing, inventory, HR... — each with its own
vocabulary, owners and rules, usually its own directories or tables): split.

- `domains.md` becomes the **map**: one line per domain, the boundaries between them,
  the entities and events that cross a boundary, and who owns each hand-off.
- One `domain-<name>.md` per domain: its life cycle, glossary, profiles and the rules
  only it obeys. Its `paths:` declare the domain's code, so drift is caught at commit.
- Every domain note gets a **domain rule** of the same name (`rules/domain-<name>.md`)
  whose globs cover the whole domain and whose first line orders reading the note —
  that is what makes the agent read it when it navigates into the domain, not only
  when it edits. Hand them to `/agent-kit:rules`; they are mandatory, not candidates.
- A module inside a domain stays a section of the domain note until it outgrows one
  read; then it gets its own `module-*.md` with the narrower glob, and the domain
  note's `paths:` drop it (notes must not overlap). The domain rule keeps covering it.

One domain → keep the single `domains.md`, no domain rules.

## Phase 5 — Deepen module by module, on demand

**Do not write twelve deep notes at once.** The return drops fast, and what you wrote
about a module nobody touched rots before its first read. Deepen a module when a real
task touches it — that is what `/agent-kit:memory <area>` is for.

A mature module note has: main entities and tables, the non-obvious business rules with
their why, external integrations, and the traps already paid for.

When closing the note, ask whether anything is left that the agent must obey **without
having read the note**. If so, it is a rule candidate for that area — five to ten lines,
ending with the pointer to the note. Hand it to `/agent-kit:rules <area>`.

## Phase 6 — Close the index → `MEMORY.md`

```markdown
# <Project> — Knowledge Base (index)

<one paragraph: what the system is, for whom, since when, on which stack>

This directory is a **knowledge graph**: each note describes one part of the system and
links to its neighbours. Start with the [architecture](architecture.md).

## Graph map

### Foundations
- [Business domains](domains.md) — <hook>
- [Conventions and non-negotiables](conventions.md) — <hook>
- [Overall architecture](architecture.md) — <hook>

### Business domains (when there is more than one)
- [...](domain-....md) — <hook>

### Business modules
- [...](module-....md) — <hook>

### Secondary entry points and integrations
- [...](...) — <hook>
```

Cut the sections that do not apply. The hook decides whether the note gets read —
**write it last**, once you know what the note became. "Describes the billing module" is
not a hook; "why renegotiation recalculates interest at settlement, not at issue" is.

Note format:

- Starts with `# Title`, and on the next line a link back to the index
  (`Back to the [index](MEMORY.md).`, translated) plus the relevant "See also" links. The
  catalog is a graph: a note that links nowhere is probably in the wrong place.
- A note that describes an area of code declares it in a `paths:` frontmatter, same
  syntax as `rules/`. That is what `memory-drift-guard` uses to block a commit that
  touches the area without bringing the note along. One glob per line — the guard does
  not expand `{a,b}`. Globs of different notes should not overlap, or one file demands
  two notes. A conceptual note, with no area of its own, has no frontmatter.

  ```markdown
  ---
  paths:
    - "jobs/**"
  ---

  # Scheduled jobs
  ```

- Kebab-case filenames, with a family prefix when there is more than one
  (`module-*`, `framework-*`).
- `conventions.md` holds the idioms and tool traps too long for `AGENTS.md`; do not
  duplicate there what `AGENTS.md` already says.

## Running this without burning the context

- **Phases 0–2 in the main flow.** They are cheap and you need that context to judge
  everything else.
- **Phases 3–5 are fan-out:** launch the `agent-kit:explorer` agent in parallel, one per
  module or area. It is exactly the case subagents are for — reads a lot, concludes
  little.
- **The explorer reports, you write.** It does not edit memory on purpose: the main flow
  sees the whole catalog and knows whether a fact goes into a new note or an existing one.
- **Never in parallel with code edits.** Mapping is reading; mixing the two yields notes
  about code you just changed yourself.

## Stopping criterion

Phases 0–4 done = minimum usable catalog. **Stop there** and go back to real work. A
catalog grows by use — each task that reveals something unrecorded becomes a new line —
not by up-front effort. Exhaustive early mapping produces volume that rots together, not
knowledge.

## Report

At the end: notes created/extended, what went into `AGENTS.md`, the open questions still
unanswered, the **domain rules** owed (one per `domain-*.md`, with its globs), and the
**rule candidates** (area + one line each) — offer `/agent-kit:rules` for them.

## Maintenance

The code is the source of truth; memory is an interpretation of it. When they diverge,
**fix the note right away**, in the same task that found it — do not leave it for later.
And fix it in place: the note describes the current state, it does not accumulate a
changelog. `rules/memory.md` says this in every session, `memory-drift-guard` enforces it
at commit time; `SKIP_MEMORY_CHECK=1` is for
when you read the note and it still holds, not for skipping the read.
