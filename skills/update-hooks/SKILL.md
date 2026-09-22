---
name: update-hooks
description: Reviews an existing harness's guards against this plugin - the copies in .agents/hooks/ and their registration, deny list and plugin entries in .agents/settings.json - and brings them up to date, showing each diff before replacing anything. Use when the user asks to update, check or repair the hooks/guards of a project that already has .agents/, after upgrading agent-kit, or as part of update-all.
---

# update-hooks

Brings `.agents/hooks/` and `.agents/settings.json` in line with the installed
`agent-kit`. The engine is a script; this skill decides what the user sees and approves.

Language: whatever you *write into the project* follows the language declared in
`AGENTS.md`; nothing here writes prose, only copies and JSON keys.

## Steps

1. **Report.** From the repository root:

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-hooks.sh"
   ```

   One finding per line: `ok`, `missing`, `outdated`, `legacy`, `linked`. Exit 0 means
   nothing to do — say so and stop. Exit 2 is an environment problem (no `.agents/`,
   invalid `settings.json`): report it, do not work around it. No `.agents/` at all →
   this is not an update, it is `/agent-kit:scaffold`.

2. **`missing`** — safe to add, nothing is replaced: guard copies, `deny` entries,
   hook registrations, the plugin and marketplace entries. List them and apply:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-hooks.sh" --apply
   ```

3. **`outdated`** — the project's copy differs from the plugin's. It may be an older
   release, or a deliberate local change: **show the diff and ask** before replacing.

   ```bash
   diff -u .agents/hooks/<guard>.sh "${CLAUDE_PLUGIN_ROOT}/hooks/<guard>.sh"
   ```

   Summarise what the new version changes (the header comment and the diff say it) and
   whether the project's copy carries anything the plugin's does not. Only on a yes:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-hooks.sh" --apply --force
   ```

   `--force` replaces every outdated copy; if the user wants to keep one, back it up
   first and restore it after, and say so in the report.

4. **`linked`** — a symlink to somewhere else (another harness package, another repo).
   Never written through, never replaced by a copy without the user deciding it: the
   owner of the link target is who updates it. Report it with the target.

5. **`legacy`** — entries under the old marketplace name `univates.br`. The script already
   moved `agent-kit` to `agent-kit@agent-kit`; what is left is other plugins or the old
   marketplace key. Tell the user, and remove only what they confirm nothing else uses.

6. **Stage** what changed, by name — the exec bit of a copy only reaches the other clones
   through git:

   ```bash
   git add .agents/settings.json .agents/hooks/<each changed guard>.sh
   ```

7. **Report**: added, replaced (with the one-line reason from the diff), kept on purpose,
   linked, legacy left. Hooks already registered in the project that are not this kit's
   (a linter, an encoding guard) are the project's — mention that they were not touched.
   The new versions act on the next tool call; no restart needed for the copies.
