#!/usr/bin/env bash
# Self-check for secret-guard.sh:  bash hooks/secret-guard.test.sh
#
# Each case builds a throwaway repo under $TMPDIR, stages content, and feeds a
# command through the hook. Exits non-zero if any case regresses.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/secret-guard.sh"
bash -n "$H" || exit 1
[ -x "$H" ] || { echo "missing exec bit: secret-guard.sh (git update-index --chmod=+x)"; exit 1; }
perl -MJSON::PP -e1 || { echo "perl with JSON::PP is required (the hook needs it too)"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# newrepo -> path to a fresh repo with one empty commit as HEAD. mktemp per call:
# a counter would not survive the $(newrepo) subshell.
newrepo() {
  local dir; dir="$(mktemp -d "$tmp/r.XXXXXX")"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '%s' "$dir"
}

fails=0
t(){ # t <cwd> <command> <expected exit>
  local out; out="$(cd "$1" && printf '{"tool_input":{"command":%s}}' "$(perl -MJSON::PP -e 'print JSON::PP->new->allow_nonref->encode($ARGV[0])' "$2")" | bash "$H" 2>&1)"
  local r=$?; local s=ok
  [ "$r" = "$3" ] || { s=FAIL; fails=$((fails+1)); }
  printf '%-4s got=%s want=%s  <- %s\n' "$s" "$r" "$3" "$2"
}

AKIA='AKIAIOSFODNN7EXAMPLE'
GHP='ghp_0123456789abcdefghijABCDEFGHIJ012345'   # ghp_ + 36 chars

echo "== clean staged content: commit passes =="
r="$(newrepo)"; printf 'hello world\n' > "$r/app.txt"; git -C "$r" add app.txt
t "$r" 'git commit -m x' 0

echo "== non-commit commands never block, even with a secret staged =="
r="$(newrepo)"; printf 'key=%s\n' "$AKIA" > "$r/c.txt"; git -C "$r" add c.txt
t "$r" 'git status' 0
t "$r" 'git log --grep commit' 0

echo "== staged secret in added lines: commit blocked =="
r="$(newrepo)"; printf 'aws=%s\n' "$AKIA" > "$r/c.txt"; git -C "$r" add c.txt
t "$r" 'git commit -m x' 2
r="$(newrepo)"; printf 'token=%s\n' "$GHP" > "$r/c.txt"; git -C "$r" add c.txt
t "$r" 'git commit -m x' 2
r="$(newrepo)"; printf -- '-----BEGIN RSA PRIVATE KEY-----\nabc\n' > "$r/id_rsa"; git -C "$r" add id_rsa
t "$r" 'git commit -m x' 2

echo "== .env staged is blocked; .env.example is not =="
r="$(newrepo)"; printf 'X=1\n' > "$r/.env"; git -C "$r" add .env
t "$r" 'git commit -m x' 2
r="$(newrepo)"; printf 'X=1\n' > "$r/.env.example"; git -C "$r" add .env.example
t "$r" 'git commit -m x' 0

echo "== -C <dir>: the index that counts is the target repo's, not cwd's =="
clean="$(newrepo)"; printf 'hello\n' > "$clean/app.txt"; git -C "$clean" add app.txt
r="$(newrepo)"; printf 'aws=%s\n' "$AKIA" > "$r/c.txt"; git -C "$r" add c.txt
t "$clean" "git -C $r commit -m x" 2
t "$r" "git -C $clean commit -m x" 0

echo "== keystore staged as binary (no + lines to scan): blocked by name =="
r="$(newrepo)"; printf -- '-----BEGIN RSA PRIVATE KEY-----\nMII\000\001bin\n' > "$r/key.p12"; git -C "$r" add key.p12
t "$r" 'git commit -m x' 2
r="$(newrepo)"; printf 'x\000y\n' > "$r/app.jks"; git -C "$r" add app.jks
t "$r" 'git commit -m x' 2

echo "== public cert in .pem is not key material: passes =="
r="$(newrepo)"; printf -- '-----BEGIN CERTIFICATE-----\nMIIabc\n' > "$r/cert.pem"; git -C "$r" add cert.pem
t "$r" 'git commit -m x' 0

echo "== secret already in HEAD, unrelated clean change: not blocked =="
r="$(newrepo)"; printf 'aws=%s\n' "$AKIA" > "$r/old.txt"
git -C "$r" add old.txt; git -C "$r" -c user.email=t@t -c user.name=t commit -q -m seed
printf 'clean\n' > "$r/new.txt"; git -C "$r" add new.txt
t "$r" 'git commit -m x' 0

echo "== -am auto-stages a tracked file: secret still caught =="
r="$(newrepo)"; printf 'ok\n' > "$r/t.txt"
git -C "$r" add t.txt; git -C "$r" -c user.email=t@t -c user.name=t commit -q -m seed
printf 'aws=%s\n' "$AKIA" > "$r/t.txt"    # modified, NOT staged
t "$r" 'git commit -am x' 2

echo "== no JSON parser: a visible error (exit 1), not a silent pass =="
mkdir -p "$tmp/noperl" && printf '#!/bin/sh\nexit 127\n' >"$tmp/noperl/perl" && chmod +x "$tmp/noperl/perl"
out="$(printf '{}' | PATH="$tmp/noperl:$PATH" bash "$H" 2>&1)"; r=$?
if [ $r = 1 ] && grep -q "NOT running" <<<"$out"; then echo "ok   parser missing -> exit 1"; else echo "FAIL parser missing -> got $r: $out"; fails=$((fails+1)); fi

echo "failures=$fails"
[ "$fails" -eq 0 ]
