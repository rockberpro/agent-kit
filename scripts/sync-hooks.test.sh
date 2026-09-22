#!/usr/bin/env bash
# Self-check for sync-hooks.sh:  bash scripts/sync-hooks.test.sh
#
# Each case runs in a throwaway project under $TMPDIR. Exits non-zero if any case regresses.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync-hooks.sh"
KIT="$(dirname "$H")/.."
bash -n "$H" || exit 1
[ -x "$H" ] || { echo "missing exec bit: sync-hooks.sh (git update-index --chmod=+x)"; exit 1; }
command -v jq >/dev/null || { echo "jq is required (the script needs it too)"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
# mktemp, not a counter: proj runs in $(...), a subshell, so a counter would never move.
proj() { local d; d="$(mktemp -d "$tmp/p.XXXX")" && mkdir -p "$d/.agents" && printf '%s' "$d"; }
check() { # check <label> <condition...>
  local s=ok; "${@:2}" >/dev/null 2>&1 || { s=FAIL; fails=$((fails+1)); }
  printf '%-4s %s\n' "$s" "$1"
}
run() { ( cd "$1" && shift && bash "$H" "$@" ); }
S=.agents/settings.json

echo "== fresh .agents/: report, apply, then clean =="
p="$(proj)"
run "$p" >/dev/null; r=$?
check "report exits 1 with things missing"      test $r = 1
check "report writes nothing"                    test ! -e "$p/$S" -a ! -e "$p/.agents/hooks/master-guard.sh"
run "$p" --apply >/dev/null; r=$?
check "apply exits 0"                            test $r = 0
check "guards copied, identical, executable"     bash -c "for g in master-guard secret-guard memory-drift-guard; do cmp -s '$KIT/hooks/'\$g.sh '$p/.agents/hooks/'\$g.sh && [ -x '$p/.agents/hooks/'\$g.sh ] || exit 1; done"
check "settings: 3 guards, 5 denies, plugin"     jq -e '(.hooks.PreToolUse[0].hooks | length) == 3 and (.permissions.deny | length) == 5 and .enabledPlugins["agent-kit@agent-kit"]' "$p/$S"
run "$p" >/dev/null; r=$?
check "second report is clean (exit 0)"          test $r = 0

echo "== existing settings: merge, keep the project's, migrate the old name =="
p="$(proj)"
cat > "$p/$S" <<'JSON'
{
  "extraKnownMarketplaces": {"univates.br": {"source": {"source": "url", "url": "https://example.test/kit.git"}}},
  "enabledPlugins": {"agent-kit@univates.br": true, "other@univates.br": true},
  "permissions": {"allow": ["Bash(make:*)"], "deny": ["Bash(rm -rf:*)", "Bash(git add -A:*)"]},
  "hooks": {"PreToolUse": [
    {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "bash x/php-check.sh"}]},
    {"matcher": "Bash", "hooks": [{"type": "command", "command": "D=\"$(git rev-parse --show-toplevel)\"; bash \"$D/.agents/hooks/master-guard.sh\""}]}
  ]}
}
JSON
out="$(run "$p" --apply)"; r=$?
check "exit 1: legacy entries are left for the user" test $r = 1
check "legacy univates.br reported"              grep -q '^legacy .*univates.br' <<<"$out"
check "project allow/deny/hooks kept"            jq -e '.permissions.allow == ["Bash(make:*)"] and (.permissions.deny | index("Bash(rm -rf:*)")) and (.hooks.PreToolUse[0].hooks[0].command == "bash x/php-check.sh")' "$p/$S"
check "no duplicated deny"                       jq -e '[.permissions.deny[] | select(. == "Bash(git add -A:*)")] | length == 1' "$p/$S"
check "master-guard not re-registered"           jq -e '[.hooks.PreToolUse[].hooks[].command | select(contains("master-guard.sh"))] | length == 1' "$p/$S"
check "missing guards join the Bash group"       jq -e '(.hooks.PreToolUse[1].hooks | length) == 3' "$p/$S"
check "plugin migrated, source carried over"     jq -e '.enabledPlugins["agent-kit@agent-kit"] and (.enabledPlugins["agent-kit@univates.br"] | not) and .extraKnownMarketplaces["agent-kit"].source.url == "https://example.test/kit.git"' "$p/$S"
check "other plugins untouched"                  jq -e '.enabledPlugins["other@univates.br"] and .extraKnownMarketplaces["univates.br"]' "$p/$S"

echo "== outdated guard copy: reported, replaced only with --force =="
p="$(proj)"
run "$p" --apply >/dev/null
echo '# local change' >> "$p/.agents/hooks/secret-guard.sh"
out="$(run "$p")"; r=$?
check "report flags it, exit 1"                  bash -c "[ $r = 1 ] && grep -q '^outdated .agents/hooks/secret-guard.sh' <<<'$out'"
run "$p" --apply >/dev/null
check "--apply alone keeps the local copy"       grep -q '# local change' "$p/.agents/hooks/secret-guard.sh"
run "$p" --apply --force >/dev/null; r=$?
check "--force replaces it, exit 0"              bash -c "[ $r = 0 ] && cmp -s '$KIT/hooks/secret-guard.sh' '$p/.agents/hooks/secret-guard.sh'"

echo "== symlinked copies belong elsewhere: never written through =="
p="$(proj)"; mkdir -p "$p/pkg" "$p/.agents/hooks"; echo '# pkg' > "$p/pkg/master-guard.sh"
ln -s ../../pkg/master-guard.sh "$p/.agents/hooks/master-guard.sh"
out="$(run "$p" --apply --force)"; r=$?
check "exit 1: the link is left for the user"   test $r = 1
check "reported as linked"                       grep -q '^linked .*master-guard.sh' <<<"$out"
check "link target untouched"                    bash -c "[ \"\$(cat '$p/pkg/master-guard.sh')\" = '# pkg' ] && [ -L '$p/.agents/hooks/master-guard.sh' ]"
check "the other guards still installed"         test -f "$p/.agents/hooks/secret-guard.sh" -a ! -L "$p/.agents/hooks/secret-guard.sh"

echo "== refuses instead of guessing =="
mkdir -p "$tmp/none"
run "$tmp/none" --apply >/dev/null 2>&1; r=$?
check "no .agents/: exit 2"                      test $r = 2
p="$(proj)"; echo '{ broken' > "$p/$S"
run "$p" --apply >/dev/null 2>&1; r=$?
check "invalid settings.json: exit 2, untouched" bash -c "[ $r = 2 ] && [ \"\$(cat '$p/$S')\" = '{ broken' ]"
run "$p" --bogus >/dev/null 2>&1; r=$?
check "unknown flag: exit 2"                     test $r = 2

echo "failures=$fails"
[ "$fails" -eq 0 ]
