---
name: update-rules
description: Reviews an existing .agents/rules/ and fixes what is missing or has drifted - the mandatory memory and commit rules, dead or too-broad globs, duplicates of AGENTS.md or of each other, rules that grew into explanations, broken pointers to notes, rules in the wrong language, and rule candidates that memory notes gained since. Use when the user asks to update, review, audit or prune the rules of a project that already has them, or as part of update-all.
---

# update-rules

Review, not creation: `rules/` exists and this pass finds where it stopped matching the
repository. Checking is reading — do not ask to read. **Ask before writing**, with the
list of findings and the fix proposed for each; deleting a rule always needs a yes.

No `.agents/rules/` or only `memory.md` in it → that is `/agent-kit:rules` (first pass).
Say so and stop.

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
     one of the bullets the `rules` skill always includes (e.g. never co-author a commit)
     → propose adding it, translated. The co-author bullet is not a duplicate of
     `attribution` in `settings.json`: that setting binds Claude Code only.
   - Every `.agents/memory/domain-*.md` has `rules/domain-*.md` of the same name, whose
     first line orders reading that note and whose globs cover the whole domain. Missing
     or without that line → write it the way the `rules` skill does (no policy in it).
     A domain rule whose note is gone → propose deleting it.

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
