#!/usr/bin/env bash
# Self-check for master-guard.sh:  bash hooks/master-guard.test.sh
#
# Runs every case inside throwaway repos under $TMPDIR, so it never switches
# branches or touches the real worktree. Exits non-zero if any case regresses.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/master-guard.sh"
bash -n "$H" || exit 1
# The exec bit has to survive the clone: git records it, a plain `cp` does not.
[ -x "$(dirname "$H")/master-guard.sh" ] || { echo "missing exec bit: master-guard.sh (git update-index --chmod=+x)"; exit 1; }
perl -MJSON::PP -e1 || { echo "perl with JSON::PP is required (the hook needs it too)"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A repo whose HEAD is $1. The hook reads the branch from the cwd, so each case
# runs with cwd inside the matching repo.
mkrepo() {
  local dir="$tmp/$1"
  mkdir -p "$dir" && git -C "$dir" init -q -b "$1" \
    && git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '%s' "$dir"
}
on_master="$(mkrepo master)"
on_feature="$(mkrepo my-branch)"

fails=0
t(){ # t <cwd> <command> <expected exit>
  local out; out="$(cd "$1" && printf '{"tool_input":{"command":%s}}' "$(perl -MJSON::PP -e 'print JSON::PP->new->allow_nonref->encode($ARGV[0])' "$2")" | bash "$H" 2>&1)"
  local r=$?; local s=ok
  [ "$r" = "$3" ] || { s=FAIL; fails=$((fails+1)); }
  printf '%-4s got=%s want=%s  <- %s\n' "$s" "$r" "$3" "$2"
}
feat(){ t "$on_feature" "$1" "$2"; }
mast(){ t "$on_master"  "$1" "$2"; }

echo "== feature branch: only pushes aimed at master/main are blocked =="
feat 'git commit -m x' 0
feat 'git merge origin/master' 0
feat 'git reset --hard HEAD~1' 0
feat 'git push -u origin my-branch' 0
feat 'git push origin main-fix' 0
feat 'git push origin feat_main_menu' 0
feat 'git push origin master:staging' 0
feat 'git log --oneline origin/master' 0
feat 'git fetch origin master' 0
feat 'echo "push to master later"' 0
feat 'git push origin master' 2
feat 'git push origin main' 2
feat 'git push origin HEAD:master' 2
feat 'git push origin mine:master' 2
feat 'git push origin refs/heads/master' 2
feat 'git push origin HEAD:refs/heads/main' 2
feat 'git push origin :master' 2
feat 'git push origin +master' 2
feat 'git push --force origin master' 2
feat 'git push origin master --force' 2
feat 'git push --mirror origin' 2
feat 'git push --all origin' 2
feat 'git add . && git push origin master' 2

echo "== -C <dir>: the branch that counts is the target repo's, not cwd's =="
feat "git -C $on_master commit -m x" 2
feat "git -C $on_master cherry-pick abc123" 2
mast "git -C $on_feature commit -m x" 0
feat "git -C /nope/missing commit -m x" 0

echo "== feature branch: commit-writing verbs are fine there =="
feat 'git cherry-pick abc123' 0
feat 'git revert HEAD' 0
feat 'git rebase master' 0

echo "== on master: every verb that writes a commit is blocked =="
mast 'git cherry-pick abc123' 2
mast 'git revert HEAD' 2
mast 'git revert --no-edit HEAD' 2
mast 'git rebase my-branch' 2
mast 'git am patch.mbox' 2
mast 'git cherry-pick --abort' 0
mast 'git rebase --continue' 0
mast 'git am --skip' 0
mast 'git commit -m "handle --abort in the sequencer"' 2

echo "== on master: commit/merge/reset --hard/push all blocked =="
mast 'git commit -m x' 2
mast 'git -C . commit -m x' 2
mast 'git -c user.email=a@b commit -m x' 2
mast 'git merge my-branch' 2
mast 'git merge --no-ff my-branch' 2
mast 'git reset --hard' 2
mast 'git reset --hard HEAD~1' 2
mast 'git push' 2
mast 'git push -u origin my-branch' 2
mast 'git merge --abort' 0
mast 'git reset HEAD~1' 0
mast 'git reset -- file.php' 0
mast 'git status' 0
mast 'git fetch' 0
mast 'git log --merges' 0
mast 'git log --grep commit' 0
mast 'echo "git commitment"' 0

echo "== no JSON parser: a visible error (exit 1), not a silent pass =="
mkdir -p "$tmp/noperl" && printf '#!/bin/sh\nexit 127\n' >"$tmp/noperl/perl" && chmod +x "$tmp/noperl/perl"
out="$(printf '{}' | PATH="$tmp/noperl:$PATH" bash "$H" 2>&1)"; r=$?
if [ $r = 1 ] && grep -q "NOT running" <<<"$out"; then echo "ok   parser missing -> exit 1"; else echo "FAIL parser missing -> got $r: $out"; fails=$((fails+1)); fi

echo "failures=$fails"
[ "$fails" -eq 0 ]
