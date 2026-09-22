#!/usr/bin/env bash
# PreToolUse guard for Bash.
#
# Blocks `git commit` when the content about to be committed contains an obvious
# secret: a private-key header, a well-known token format (AWS/GitHub/Slack/GCP),
# or a `.env`/keystore file being added. A secret that lands in a commit is a secret leaked
# (it survives in history even if a later commit removes it), so the gate is the
# commit, not the push.
#
# Scans only ADDED lines, so a secret already in history does not block unrelated
# commits. Named-format tokens only — no entropy heuristics — to keep false
# positives near zero.
#
# Fails OPEN: any internal error exits 0 so the session is never wedged.
set -uo pipefail

payload="$(cat)" || exit 0
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -z "$cmd" ] && exit 0

# Match `git [global options] commit` (handles `git -C x commit`, `&&` chains).
# Same matcher master-guard uses, so `git log --grep commit` does not trip it.
has_verb() {
  printf '%s' "$cmd" | grep -Eq \
    "(^|[^[:alnum:]_-])git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+$1([[:space:]]|\$)"
}

# Cheap gate: only commits are interesting. Everything else exits before touching git.
has_verb commit || exit 0

# `git -C <dir>` commits in another repo, so the index has to be read there and not in
# cwd. Same block master-guard uses — see the note there on what it does not cover.
for d in $(printf '%s' "$cmd" | grep -Eo -- '-C[[:space:]]+[^[:space:];&|]+' | sed -E 's/^-C[[:space:]]+//'); do
  cd "$d" 2>/dev/null || exit 0
done

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# `git commit -a`/`-am` auto-stages tracked modifications at commit time, so those
# changes are not in the index yet — diff against HEAD to see what the commit will
# actually contain. A plain commit only takes what is already staged.
# A short-flag cluster containing `a` (-a, -am, -ma...) or --all. Over-detecting is
# safe here: HEAD is a superset of --cached, so at worst we scan a bit more.
if printf '%s' "$cmd" | grep -Eq -- '(^|[[:space:]])(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'; then
  range=(HEAD)
else
  range=(--cached)
fi

files="$(git diff "${range[@]}" --name-only 2>/dev/null)" || exit 0
# Added lines only: `+` but not the `+++ b/file` header.
added="$(git diff "${range[@]}" 2>/dev/null | grep '^+' | grep -v '^+++')"

# A committed .env carries real secrets; .env.example/.sample/.template/.dist are
# the safe scaffolding variants.
env_hit="$(printf '%s\n' "$files" | grep -E '(^|/)\.env' | grep -Evi '\.(example|sample|template|dist)$')"

# A binary diff carries no `+` lines, so the content scan below cannot see inside a
# keystore — the filename is the only signal. These formats are always key material;
# a private key in a text `.pem` is caught by the header pattern instead, which keeps
# public certs (also `.pem`) from tripping the guard.
key_hit="$(printf '%s\n' "$files" | grep -Ei '\.(p12|pfx|jks|keystore)$')"

# Well-known token formats. Precise on purpose.
patterns='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[opsur]_[0-9A-Za-z]{36}|xox[baprs]-[0-9A-Za-z-]{10,}|AIza[0-9A-Za-z_-]{35}'
tok_hit="$(printf '%s\n' "$added" | grep -Eo -- "$patterns" | sort -u)"

[ -z "$env_hit" ] && [ -z "$key_hit" ] && [ -z "$tok_hit" ] && exit 0

{
  echo "BLOCKED by secret-guard: this commit would introduce what looks like a secret."
  echo
  [ -n "$env_hit" ] && { echo "  env file(s) staged:"; printf '%s\n' "$env_hit" | sed 's/^/    /'; }
  [ -n "$key_hit" ] && { echo "  key file(s) staged:"; printf '%s\n' "$key_hit" | sed 's/^/    /'; }
  [ -n "$tok_hit" ] && { echo "  secret pattern(s) in added lines:"; printf '%s\n' "$tok_hit" | sed 's/^/    /'; }
  echo
  echo "Move the value to a secret manager / env var and git-ignore the file, then commit."
  echo "If it is a genuine false positive, the user has to run the commit themselves."
} >&2
exit 2
