#!/usr/bin/env bash
# Brings a project's .agents/hooks/ and .agents/settings.json in line with this plugin.
#
#   sync-hooks.sh            report only (default)
#   sync-hooks.sh --apply    create what is missing; never replace what exists
#   sync-hooks.sh --apply --force   also replace guard copies that differ from the plugin
#
# Run from the project root. The scaffold uses --apply; update-hooks reports first, shows
# the diffs, and only then --force. Every line of output is one finding:
#   ok|missing|outdated|added|updated|legacy|linked <what>
# A symlink (hook or settings.json) belongs to whatever it points at — another package,
# another repo — so it is reported as `linked` and never written through.
# Exit: 0 nothing left to do, 1 findings left (report mode, or outdated without --force),
# 2 usage/environment error.
set -uo pipefail

apply=0; force=0
for a in "$@"; do
  case "$a" in
    --apply) apply=1 ;;
    --force) force=1 ;;
    *) echo "usage: $0 [--apply [--force]]" >&2; exit 2 ;;
  esac
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARDS="master-guard secret-guard memory-drift-guard"
URL="https://gitlab.univates.br/gitlab/pacotes/agent-kit.git"
DENY='["Bash(git add -A:*)","Bash(git add --all:*)","Bash(git add .:*)","Bash(git add -u:*)","Bash(git add :/:*)"]'
S=.agents/settings.json
left=0
say() { printf '%-8s %s\n' "$1" "$2"; case "$1" in missing|outdated|legacy|linked) left=1 ;; esac; }

[ -d .agents ] || { echo "no .agents/ here — run from the project root, after the scaffold" >&2; exit 2; }
mkdir -p .agents/hooks

# --- guard copies ---------------------------------------------------------------------
for g in $GUARDS; do
  dst=".agents/hooks/$g.sh" src="$KIT/hooks/$g.sh"
  if [ -L "$dst" ]; then
    say linked "$dst -> $(readlink "$dst") (managed there; left alone)"
  elif [ ! -e "$dst" ]; then
    if [ $apply = 1 ]; then cp "$src" "$dst" && chmod +x "$dst" && say added "$dst"; else say missing "$dst"; fi
  elif ! cmp -s "$src" "$dst"; then
    if [ $apply = 1 ] && [ $force = 1 ]; then cp "$src" "$dst" && chmod +x "$dst" && say updated "$dst"; else say outdated "$dst"; fi
  else
    say ok "$dst"
  fi
done

# --- settings.json --------------------------------------------------------------------
cmd_of() { printf 'bash "$CLAUDE_PROJECT_DIR/.agents/hooks/%s.sh"' "$1"; }

if [ -L "$S" ]; then say linked "$S -> $(readlink "$S") (managed there; left alone)"; exit 1; fi
if [ ! -e "$S" ]; then
  if [ $apply = 0 ]; then say missing "$S"; exit 1; fi
  hooks="$(for g in $GUARDS; do jq -n --arg c "$(cmd_of "$g")" '{type:"command",command:$c}'; done | jq -s .)"
  jq -n --arg url "$URL" --argjson deny "$DENY" --argjson hooks "$hooks" '{
    extraKnownMarketplaces: {"agent-kit": {source: {source: "url", url: $url}}},
    enabledPlugins: {"agent-kit@agent-kit": true},
    permissions: {
      allow: ["Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)"],
      deny: $deny
    },
    hooks: {PreToolUse: [{matcher: "Bash", hooks: $hooks}]}
  }' > "$S" && say added "$S"
  exit $left
fi

jq -e . "$S" >/dev/null 2>&1 || { echo "$S is not valid JSON — fix it by hand first" >&2; exit 2; }
new="$(jq . "$S")"
edit() { new="$(printf '%s' "$new" | jq "$@")"; }
has() { printf '%s' "$new" | jq -e "$@" >/dev/null 2>&1; }

# Marketplace + plugin. The marketplace was once called univates.br: carry its source over
# instead of guessing a URL, and leave the old key for the user — other plugins may use it.
if has '.extraKnownMarketplaces["agent-kit"]'; then say ok "$S extraKnownMarketplaces.agent-kit"
else
  src="$(printf '%s' "$new" | jq -c '.extraKnownMarketplaces["univates.br"].source // empty')"
  [ -n "$src" ] || src="$(jq -nc --arg url "$URL" '{source:"url",url:$url}')"
  edit --argjson s "$src" '.extraKnownMarketplaces["agent-kit"] = {source: $s}'
  say "$([ $apply = 1 ] && echo added || echo missing)" "$S extraKnownMarketplaces.agent-kit"
fi
if has '.enabledPlugins["agent-kit@agent-kit"]'; then say ok "$S enabledPlugins.agent-kit@agent-kit"
else
  edit '.enabledPlugins["agent-kit@agent-kit"] = true | del(.enabledPlugins["agent-kit@univates.br"])'
  say "$([ $apply = 1 ] && echo added || echo missing)" "$S enabledPlugins.agent-kit@agent-kit"
fi
for k in $(printf '%s' "$new" | jq -r '(.extraKnownMarketplaces // {} | keys[]), (.enabledPlugins // {} | keys[]) | select(test("univates\\.br"))'); do
  say legacy "$S $k (old marketplace name; remove it if nothing else uses it)"
done

# deny entries: added one by one, whatever else the project denies stays.
for d in $(printf '%s' "$DENY" | jq -r '.[] | @base64'); do
  d="$(printf '%s' "$d" | base64 -d)"
  if has --arg d "$d" '.permissions.deny // [] | index($d)'; then continue; fi
  edit --arg d "$d" '.permissions.deny = ((.permissions.deny // []) + [$d])'
  say "$([ $apply = 1 ] && echo added || echo missing)" "$S permissions.deny $d"
done

# Hook registrations: a guard counts as registered if any PreToolUse command names it,
# however the project spelled the path. Missing ones join the first Bash group.
for g in $GUARDS; do
  if has --arg g "$g.sh" '[.hooks.PreToolUse[]?.hooks[]?.command | select(contains($g))] | length > 0'; then
    say ok "$S hook $g"; continue
  fi
  edit --arg c "$(cmd_of "$g")" '
    .hooks.PreToolUse //= [] |
    if any(.hooks.PreToolUse[]; .matcher == "Bash")
    then (first(.hooks.PreToolUse | to_entries[] | select(.value.matcher == "Bash") | .key)) as $i
         | .hooks.PreToolUse[$i].hooks += [{type:"command",command:$c}]
    else .hooks.PreToolUse += [{matcher:"Bash",hooks:[{type:"command",command:$c}]}] end'
  say "$([ $apply = 1 ] && echo added || echo missing)" "$S hook $g"
done

if [ $apply = 1 ] && [ "$new" != "$(jq . "$S")" ]; then printf '%s\n' "$new" > "$S"; fi
exit $left
