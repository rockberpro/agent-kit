---
name: update-all
description: Reviews a whole existing harness in one pass - .agents/ structure, hooks and settings, memory catalog, rules - creating what is missing and updating what drifted, asking before any replacement or rewrite. Use when the user asks to update, upgrade, review or repair the agent harness (or ".agents") of a project that already has one, typically after upgrading agent-kit.
---

# update-all

The four update passes in dependency order, one consolidated report at the end. Each pass
keeps its own rule about what needs a yes; do not batch the questions of a later pass
into an earlier one — its findings depend on what the earlier pass fixed.

No `.agents/` at all → this is not an update: run `/agent-kit:scaffold` instead and stop.

## Order

1. **Structure — `/agent-kit:scaffold`.** It is idempotent: on an existing harness it only
   creates what is missing (symlinks, `AGENTS.md` sections, the language line, the
   anti-drift rule) and touches nothing that exists. Settle the language here — every
   later pass reads it from `AGENTS.md`.
2. **Hooks — `/agent-kit:update-hooks`.** Guards and `settings.json`; outdated copies are
   replaced only after their diff is shown.
3. **Memory — `/agent-kit:update-memory`.** Before rules: rules point at notes, and the
   rule candidates come from what the notes say now.
4. **Rules — `/agent-kit:update-rules`.** Last, over the notes as they are after step 3.

A pass with nothing to do reports "nothing to do" in one line and the next one starts.

## Report

One section per pass: created, updated, left on purpose (and why), what still needs the
user (legacy entries, linked hooks, rewrites declined). Then the follow-ups the passes
listed — `/agent-kit:memory <area>`, `/agent-kit:rules <area>` — as one list. Everything
changed is staged by name; committing follows the project's `rules/commit.md`.
