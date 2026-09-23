---
name: rules
description: Maps the project's path-scoped rules into .agents/rules/ - short imperative instructions the harness injects when a matching file is read, plus the always-on ones (the agent's git limits). Use when the user asks to create or map rules, after the memory skill reports rule candidates, or when an area keeps getting edited wrong. Pass an area (a module, directory or subject) to write just that one.
argument-hint: "[area]"
---

# rules

`.agents/rules/` (seen as `.claude/rules/`) holds instructions that apply to part of the
repository and must arrive **before** the first wrong line. Every `.md` in there is
loaded; what changes is when:

- **no frontmatter** — at the start of every session;
- **with `paths:`** — when the agent reads a file matching one of the globs.

```markdown
---
paths:
  - "src/billing/**"
---

# Billing — rules

- Never change an invoice amount without recording the history entry.
- Before touching the bank file layout: `.agents/memory/module-billing.md`.
```

**No README or index in `rules/`**: every `.md` there becomes an instruction.

Survey before writing; **ask before writing**, listing the rules and their globs. Every
rule you write is project content — a real file, versioned by the project. Filenames in
English kebab-case.

## Language of what you write

The language of `.agents/` is a project fact, declared once in the root `AGENTS.md` (the
line under *Memory Catalog* naming it, with a tag such as `pt-BR`) — read it from there,
do not re-guess it. If `AGENTS.md` does not declare it yet, settle it the way
`/agent-kit:scaffold` does (propose from README, code comments and `git log` subjects,
**confirm with the user**, add the line) before writing anything.

Every rule's text and heading go in that language, the commit policy included — its
*message* language is a separate question you ask (below), not this one.

## Arguments

- **No argument** — full pass: the always-on rules, the read rules (one per note that
  owns an area, below), then one rule per area that has a candidate. Reviewing rules that already exist — dead globs, duplicates,
  language — is `/agent-kit:update-rules`.
- **An area** (`$ARGUMENTS`) — only that area's rule. Read its memory note first; if
  there is none, run `/agent-kit:memory <area>` first or ask the user whether to write
  the rule without one.

## Rule or memory note?

They do not compete — the same area usually has one of each, and the rule ends pointing
at the note (`details in .agents/memory/<note>.md`).

| | `rules/` | `memory/` |
|---|---|---|
| Answers | what to **obey** when editing | what to **understand** to decide |
| Form | imperative, tens of lines | explanatory, with the why and the measurements |
| Loaded by | the harness, on reading a matching file | the agent, when it judges it needs it |
| Cost | paid on every matching Read — hence short | paid only when opened |

Test for a rule: *would an agent that never opened the note still break something here?*
If not, it stays a note.

## Where candidates come from

1. **The memory report** — the rule candidates the `memory` skill listed.
2. **Existing notes** — each `module-*.md` / area note: the lines that are prohibitions
   or mandatory steps ("never", "always", "before X do Y") are the rule; the rest stays.
3. **`AGENTS.md`** — an editing constraint that only applies to some files (a language,
   a directory, a generated file) is costing every session; move it to a rule with the
   right `paths:` and leave `AGENTS.md` with the facts.
4. **History** — `git log` reverts, "fix"/"hotfix" commits clustering in one area, and
   the traps the user tells you about.
5. **Generated or vendored code** — `vendor/`, `dist/`, generated clients, migrations
   already applied: a two-line "do not edit; regenerate with <command>" rule is often the
   most valuable one.

## Always-on rules (no `paths:`)

Paid in every session, so keep them to the few that apply to **any** file.

**`rules/memory.md` — mandatory whenever `.agents/memory/` exists**, on any pass, with or
without an area argument. It is the anti-drift rule: fix the note in the same task that
made it wrong. If it is missing, create it — no need to ask, it carries no policy:

```bash
[ -d .agents/memory ] && [ ! -e .agents/rules/memory.md ] && mkdir -p .agents/rules \
  && cp "${CLAUDE_PLUGIN_ROOT}/templates/rules/memory.md" .agents/rules/memory.md
```

Freshly copied, translate it into the project's language (keep the filename). Never
overwrite an existing one.

The other one nearly every project wants is the agent's git limit, `rules/commit.md`. Its content is
policy, and policy is the user's call — **ask**, do not assume, and read `git log` to
propose defaults that match the history:

- May the agent run `git commit` on its own, or only stage and hand over the message?
- Message format: language, prefix/scope convention, ticket reference? (Default: one
  line.)
- May the agent push? (Default: never.)
- Should commits and PRs made with an agent (Claude, Codex, ...) keep the agent as
  co-author (`Co-Authored-By:` trailer, "Generated with" footer), or turn that off?
  Propose what `git log --format=%B` shows: trailers already there → keep, none → off.
  Never decide it for the user.

Ask them in the user's language — the one they write to you in — not in this skill's
English. Then write it as imperative bullets. Always include, whatever the answers:

- never `git add -A` / `git add .` / `git add -u` — stage only the files of the change,
  after `git status` and `git diff`; a credential, real config or unrelated artifact
  showing up means stop and flag it;
- never commit on `main`/`master`: create a branch before the first commit;
- commit messages are concise and clear, one line saying what changed; a body only when
  the why is not obvious from the diff;
- pull requests are short and objective: what changed and why, a few bullets at most —
  no walls of text, no restating the diff, no feature tours;
- do not skip hooks or signing (`--no-verify`, `--no-gpg-sign`) unless asked;
- close with: `master-guard`, `secret-guard` and the `deny` in `settings.json` are the
  net for mistakes, not the rule.

The co-author answer goes in two places, both always, so they never disagree:

- **off** → the bullet "never co-author a commit or PR: no `Co-Authored-By:` trailer or
  any other agent attribution in the message or description", and
  `"attribution": { "commit": "", "pr": "" }` in `.agents/settings.json`;
- **keep** → the bullet "commits and PRs keep the agent's co-author attribution", and no
  `attribution` key in `settings.json` (Claude Code's default adds it); remove an empty
  one there.

The setting binds Claude Code only; the bullet reaches any other agent that reads
`.agents/`. Edit only that key of `settings.json` — the rest is `update-hooks`' — and
stage it with the rule.

If the answers carry a *why* worth keeping (a past incident, a team agreement), that goes
in `.agents/memory/commit.md`, and the rule points at it.

## Read rules — mandatory for every note that owns an area

A note nobody opens is not knowledge. The harness injects a rule the moment the agent
reads a matching file, so a rule is how reading the note stops being optional — at the
first Read in the area, before the first wrong line, not only at commit. Two kinds of
note own an area, and each gets a **read rule** of the same name in `rules/`
(`<note>.md` → `rules/<note>.md`):

- **a domain note** — frontmatter says `kind: domain`. Its rule is the **domain rule**:
  its globs cover the whole domain, including modules that have their own notes (the
  note's `paths:` may be narrower; the rule's may not);
- **any other note with `paths:`** — a module, a job, an integration, a single trap. Its
  rule's globs are the note's `paths:`, no narrower.

The declaration decides — `kind: domain` or `paths:` — never the filename. A conceptual
note (no `paths:`, no `kind: domain`) gets none. No policy in a read rule, so no
question to ask beyond listing it with the others.

`domains.md` maps several domains but no note declares `kind: domain` → do not skip in
silence: list the notes it links to and ask which are domains, then write the `kind:`
line into each (`domain` or `module`) before writing the rules.

- **First line orders the read**, before anything else:

  ```markdown
  ---
  paths:
    - "src/billing/**"
  ---

  # Billing domain

  - Before reading further or changing anything here, read
    `.agents/memory/domain-billing.md` — and `domains.md` if the task crosses into
    another domain.
  - <the area's prohibitions, mandatory steps or invariants, if any — none is fine>
  ```

  For a note that is not a domain, the first line names just that note. A rule that is
  only the read order is complete; do not pad it with rules the area does not have.
- **Globs may overlap** between read rules, unlike notes' `paths:`: a file in a module
  of a domain loads both rules and the agent reads both notes — which is the point.
- **One rule per area.** An area whose note already has a path-scoped rule gets the read
  order as that rule's first line, not a second file.

The rest follows the path-scoped rules below.

## Path-scoped rules

For each candidate area:

- **Glob from the real layout**, checked with `git ls-files ':(glob)<glob>' | head` (the
  `:(glob)` prefix makes `**/` also match the root; git does not expand `{a,b}`, so check
  each alternative) — a glob that matches nothing is a rule that never loads; one that
  matches half the repo is an always-on rule in disguise. Brace sets are fine in the rule
  itself (`**/*.{ts,tsx}`).
- **Five to fifteen imperative lines.** When it grows past that, the excess was
  explanation: move it to the note.
- **End with the pointer** to the note that explains it.
- **One rule per area**, named after it (`billing.md`, `migrations.md`). Two rules with
  overlapping globs load together — fine when they say different things, a bug when they
  repeat each other.

Do not repeat in a rule what a hook already enforces with a clear message; say only what
the hook does *not* cover.

## Report

List created/changed/deleted rules with their globs and how many files each glob matches
(`git ls-files ':(glob)<glob>' | wc -l`), the read rules among them (one per note that
owns an area), and the candidates you left as notes on purpose.
