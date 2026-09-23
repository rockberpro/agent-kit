---
name: update-rules
description: Reviews an existing .agents/rules/ and fixes what is missing or has drifted - the mandatory memory and commit rules, dead or too-broad globs, duplicates of AGENTS.md or of each other, rules that grew into explanations, broken pointers to notes, rules in the wrong language, and rule candidates that memory notes gained since. Use when the user asks to update, review, audit or prune the rules of a project that already has them, or as part of update-all.
---

# update-rules

Review, not creation: `rules/` exists and this pass finds where it stopped matching the
repository. Checking is reading — do not ask to read. **Ask before writing**, with the
list of findings and the fix proposed for each; deleting a rule always needs a yes.

No `.agents/rules/` or only `memory.md` in it → the policy and the path-scoped rules
are `/agent-kit:rules` (first pass). Still run the read-rule bullet of check 1 here —
it carries no policy — then offer `/agent-kit:rules` and stop.

## Language

The language of `.agents/` is declared in the root `AGENTS.md` (the line under
*Memory Catalog*). Read it from there; if it is missing, settle it the way
`/agent-kit:scaffold` does (propose from README, comments and `git log`, **confirm with
the user**, add the line) before anything else. Every fix you write goes in it.

## Checks

Run all of them, then report once.

1. **Mandatory rules.**
   - `.agents/memory/` exists and `rules/memory.md` does not → create it, no need to ask
     (it carries no policy), translated:

     ```bash
     [ -d .agents/memory ] && [ ! -e .agents/rules/memory.md ] && mkdir -p .agents/rules \
       && cp "${CLAUDE_PLUGIN_ROOT}/templates/rules/memory.md" .agents/rules/memory.md
     ```

   - `rules/memory.md` exists: compare it with the template. The template gaining an
     instruction the project's copy lacks → propose adding it, translated; the project's
     own additions stay.
   - `rules/commit.md` missing → it is policy: offer `/agent-kit:rules`, which asks for it.
     Present → check it against the last few hundred `git log --format=%s` subjects; a
     rule the history contradicts is a question for the user, not a silent fix. Missing
     one of the bullets the `rules` skill always includes → propose adding it,
     translated.
   - `rules/commit.md` says nothing about agent co-authors → ask the user, in their
     language, whether commits and PRs made with an agent (Claude, Codex, ...) keep the
     agent as co-author or turn it off — propose what `git log --format=%B` shows, never
     decide it. Write the answer the way the `rules` skill does: the bullet in
     `commit.md` and the matching `attribution` in `settings.json`. An old "never
     co-author" bullet a previous version added unasked → confirm it is still wanted.
     The bullet is not a duplicate of `attribution`: that setting binds Claude Code only.
   - Every note that owns an area has its **read rule** — a rule of the same name in
     `rules/` (or the area rule that points at it) whose first line orders reading that
     note. A `kind: domain` note's globs cover the whole domain; any other note with
     `paths:` gets globs that cover at least those `paths:`. Missing, without that line,
     or with globs narrower than the note's → write or fix it the way the `rules` skill
     does (no policy in it). A read rule whose note is gone, or no longer declares
     `kind: domain` or `paths:`, → propose deleting it. No note declares `kind:` while
     `domains.md` maps several domains → say so out loud and send it to `update-memory`;
     never guess from filenames.

2. **Globs.** For each rule with `paths:`, how many files each glob matches:

   ```bash
   git ls-files ':(glob)<glob>' | wc -l   # git does not expand {a,b}: check each alternative
   ```

   Zero → the area moved or is gone: fix the glob or propose deleting the rule. A large
   share of the repository → an always-on rule in disguise: narrow it or justify it.

3. **Duplicates.** A rule restating `AGENTS.md` or another rule → keep one, delete the
   other: the same instruction in two places is the shortest path to contradictory
   instructions. A rule repeating what a hook already enforces with a clear message →
   keep only what the hook does not cover.

4. **Size.** Past fifteen imperative lines → the excess is explanation: move it into the
   area's note and leave the pointer.

5. **Pointers.** Every rule ends pointing at a note; the note exists. A broken pointer →
   fix it, or the note is missing: offer `/agent-kit:memory <area>`.

6. **Language.** A rule not in the declared language → list it and offer to translate
   (it is a rewrite).

7. **New candidates.** Notes changed since the rule of their area (or with no rule) that
   now carry a prohibition or mandatory step ("never", "always", "before X do Y"):

   ```bash
   git log --format=%h -1 -- .agents/rules/<area>.md     # then compare with the note's
   git log --format=%h -1 -- .agents/memory/<note>.md
   ```

   List them and offer `/agent-kit:rules <area>`; do not write them in this pass.

`rules/memory.md` is exempt from checks 3 and 4 while `.agents/memory/` exists — it is
short on purpose and nothing else may replace it.

To switch a rule off without deleting it (e.g. only locally), `claudeMdExcludes` in
`.agents/settings.local.json` accepts its path — offer that when the user hesitates
between keeping and deleting.

## Report

Created/changed/deleted rules with their globs and match counts, what you left and why,
and the `/agent-kit:rules <area>` follow-ups. Stage the rules you changed by name.
