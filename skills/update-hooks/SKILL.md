---
name: update-hooks
description: Reviews an existing harness's .agents/settings.json against this plugin - deny list, attribution, plugin entries left by older versions - and removes guard copies left in .agents/hooks/ by older versions, asking before removing anything. Use when the user asks to update, check or repair the hooks/guards or settings of a project that already has .agents/, after upgrading agent-kit, or as part of update-all.
---

# update-hooks

The guards run from the plugin (`hooks/guard.sh`), for whoever has it installed. What a
project carries is only `.agents/settings.json`, which denies blind `git add` and turns
off agent co-author attribution. It never names this plugin: a project's config holds
the project's policy, not the tool that wrote it.

Language: nothing here writes prose, only JSON keys.

## Steps

1. **No `.agents/` at all** → this is not an update, it is `/agent-kit:scaffold`. Stop.

2. **`settings.json`** against `${CLAUDE_PLUGIN_ROOT}/templates/settings.json`:
   - missing → copy the template.
   - present → add only what it lacks: each `deny` entry,
     `"attribution": { "commit": "", "pr": "" }`. Everything else stays. Not valid JSON →
     report it and stop; do not hand-edit around it.
   - `includeCoAuthoredBy` present → it is deprecated: propose replacing it with the
     `attribution` block above, change it only on a yes.
   - `attribution.commit` or `attribution.pr` not empty → commits or PRs get agent
     attribution again: report it, change it only on a yes.
   - entries older versions wrote about this plugin — the `agent-kit` or `univates.br`
     key in `extraKnownMarketplaces`, `agent-kit@agent-kit` or `agent-kit@univates.br`
     in `enabledPlugins` → list them and propose removing them; remove only on a yes.
     Never add them. Drop an object left empty. Say that teammates who relied on them
     keep the guards only by installing the plugin themselves (README, *Install*).

3. **Guard copies from older versions** — `.agents/hooks/{master,secret,memory-drift}-guard.sh`
   and the `PreToolUse` entries in `settings.json` that run them. With the plugin installed
   they run a second, stale copy of each check. List them and, on a yes, delete the files
   and their registrations; a copy the user changed on purpose is theirs to keep. A symlink
   points at another package: report it with its target, never write through it.

4. **Stage** what changed, by name:

   ```bash
   git add .agents/settings.json    # plus each removed copy: git rm .agents/hooks/<guard>.sh
   ```

5. **Report**: added, removed, left on purpose. Hooks in the project that are not this
   kit's (a linter, an encoding guard) are the project's — say they were not touched.
