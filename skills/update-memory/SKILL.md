---
name: update-memory
description: Reviews an existing .agents/memory/ catalog and fixes what is missing or has drifted - the language line, the anti-drift rule, index links and orphans, dead or overlapping paths globs, notes whose code changed since they were last touched, notes in the wrong language. Use when the user asks to update, review, audit or refresh the memory of a project that already has it, after a long stretch of commits, or as part of update-all.
---

# update-memory

Review, not mapping: the catalog exists and this pass finds where it stopped matching
the code. Checking is reading — do not ask to read. **Ask before writing**, with the list
of findings and the fix proposed for each.

No `.agents/memory/MEMORY.md` → there is nothing to review: that is
`/agent-kit:memory` (bootstrap). Say so and stop.

## Language

The language of `.agents/` is declared in the root `AGENTS.md` (the line under
*Memory Catalog*). Read it from there; if it is missing, settle it the way
`/agent-kit:scaffold` does (propose from README, comments and `git log`, **confirm with
the user**, add the line) before anything else. Every fix you write goes in it.

## Checks

Run all of them, then report once. Each finding: note, what is wrong, proposed fix.

1. **Anti-drift rule.** `.agents/rules/memory.md` missing → create it (no need to ask,
   it carries no policy), translated into the declared language:

   ```bash
   [ -e .agents/rules/memory.md ] || { mkdir -p .agents/rules && cp "${CLAUDE_PLUGIN_ROOT}/templates/rules/memory.md" .agents/rules/memory.md; }
   ```

2. **Index integrity.** Every link in `MEMORY.md` resolves; every note in `memory/` is
   linked from the index (an orphan is never found); every note links back to the
   index. Broken link → fix the link or drop the line; orphan → add a line with a hook.

3. **Globs.** For each note with a `paths:` frontmatter, every glob matches something:

   ```bash
   git ls-files ':(glob)<glob>' | head -1   # empty = dead glob
   ```

   A dead glob means the area moved or was deleted — find where it went, or the note
   itself is obsolete. Globs of two notes matching the same files → one file demands two
   notes; narrow one. `{a,b}` in a note's glob → split it, `memory-drift-guard` does not
   expand braces.

4. **Staleness — the one that matters.** For each note with `paths:`, the commits that
   touched its area since the note was last changed:

   ```bash
   since="$(git log -1 --format=%H -- .agents/memory/<note>.md)"
   git log --oneline "$since"..HEAD -- ':(glob)<glob1>' ':(glob)<glob2>'
   ```

   `SKIP_MEMORY_CHECK=1` commits land here too — that is the point: someone judged the
   note still held, and this pass checks. For each note with commits, read the note
   against those diffs (`git diff "$since"..HEAD -- <globs>`). Many notes → fan out to
   `agent-kit:explorer`, one per note, asking for "what in this note the diffs made
   wrong or incomplete"; you write the fixes.

5. **Area notes without `paths:`.** A note that describes a directory or module
   (`module-*`, a jobs/integration note) but has no frontmatter is invisible to the
   guard and gets no read rule. Propose the globs.

6. **Domain declaration.** The domain rules follow `kind: domain` in a note's
   frontmatter, not its filename. A `domain-*.md` without it → add `kind: domain`
   (the name already said so; no need to ask). Notes that `domains.md` links to as
   domains with no `kind:` → list them and ask which are domains; write `kind: domain`
   or `kind: module` on the answer, so the question is not asked again. Nothing to ask when `domains.md` maps a single domain.

7. **Language.** A note, heading or index line not in the declared language → list it
   and offer to translate (it is a rewrite). Glossary *terms* stay as the code names them.

8. **Gaps.** Foundation notes the index promises but that do not exist, or an area with
   heavy recent activity (`git log --since=6.months --name-only`) and no note → do not
   write them here: list them and offer `/agent-kit:memory <area>`.

## Fixing

Fix in place: a note describes the current state, it does not accumulate a changelog. Do
not invent to fill a gap — what you could not confirm goes in as explicit uncertainty.
Stage the notes you changed by name, together with nothing else.

## Report

Findings per check (cut the empty ones), what you fixed, what you left and why, and the
`/agent-kit:memory <area>` and `/agent-kit:rules <area>` follow-ups — a fixed note that
now holds a new "never"/"always" is a rule candidate.
