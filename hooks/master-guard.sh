#!/usr/bin/env bash
# PreToolUse guard for Bash.
#
# While HEAD is on master/main, blocks anything that writes a commit there
# (`commit`, `cherry-pick`, `revert`, `am`, `rebase`), plus `git merge` and
# `git reset --hard`. Also blocks any `git push` that targets master/main
# (either by being on it or by naming it in the refspec).
# Work goes on a branch and reaches master through a merge/pull request.
#
# Fails OPEN: any internal error exits 0 so the session is never wedged.
set -uo pipefail

payload="$(cat)" || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -z "$cmd" ] && exit 0

# Match `git [global options] <verb>` (handles `git -C x commit`, `&&` chains).
# Only global options may sit between `git` and the verb, so `git log --grep commit`
# and `echo "git commitment"` do not trip it.
has_verb() {
  printf '%s' "$cmd" | grep -Eq \
    "(^|[^[:alnum:]_-])git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+$1([[:space:]]|\$)"
}

# `git -C <dir>` acts on another repo, so the branch has to be read there and not in
# cwd. This process is disposable, so just move: every git call below follows. Each
# -C is relative to the previous one, hence the loop.
# ponytail: one git invocation per call assumed; in `git -C a x && git -C b y` the
# dirs stack. Paths with spaces are not matched. Both fail open, never block wrongly.
for d in $(printf '%s' "$cmd" | grep -Eo -- '-C[[:space:]]+[^[:space:];&|]+' | sed -E 's/^-C[[:space:]]+//'); do
  cd "$d" 2>/dev/null || exit 0
done

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[ -z "$branch" ] && exit 0
case "$branch" in
  master|main) on_protected=1 ;;
  *)           on_protected=0 ;;
esac

# A refspec naming master/main as the destination: `origin master`, `HEAD:master`,
# `:main` (delete), `+master` (force). `master:staging` is not a write to master.
# `--mirror`/`--all` push every ref, master included.
names_protected() {
  printf '%s' "$cmd" | grep -Eq '(^|[/:+ ])(master|main)([[:space:]]|$)' \
    || printf '%s' "$cmd" | grep -Eq -- '--(mirror|all)([[:space:]]|$)'
}

# `--abort`/`--continue`/`--quit` are recovery, never a new change: let them through.
is_recovery() { printf '%s' "$cmd" | grep -Eq -- '--(abort|continue|quit|skip)([[:space:]]|$)'; }

# Every verb that lands a commit on the current branch. Blocking only `commit` leaves
# cherry-pick/revert/am/rebase writing history just as permanently.
writes_commit() {
  local v
  for v in commit cherry-pick revert am rebase; do
    has_verb "$v" && { verb="$v"; return 0; }
  done
  return 1
}

# `commit` has no recovery mode, so a message containing `--abort` must not exempt it.
if writes_commit && [ "$on_protected" = 1 ] && { [ "$verb" = commit ] || ! is_recovery; }; then
  cat >&2 <<MSG
BLOCKED by master-guard: you are on "$branch" and "git $verb" writes a commit there.

Create a branch first, then commit there:

  git switch -c <type>_<scope>_<description>

"$branch" only receives merges. If this really must land on "$branch", the user has
to run the commit themselves.
MSG
  exit 2
fi

if has_verb merge && [ "$on_protected" = 1 ] && ! is_recovery; then
  cat >&2 <<MSG
BLOCKED by master-guard: you are on "$branch" and this command merges.

"$branch" is updated through a merge/pull request on the remote, not by a local merge.
Merge into your own branch instead, or ask the user to run it.
MSG
  exit 2
fi

if has_verb reset && [ "$on_protected" = 1 ] \
   && printf '%s' "$cmd" | grep -Eq -- '--hard([[:space:]]|$)'; then
  cat >&2 <<MSG
BLOCKED by master-guard: "git reset --hard" on "$branch" throws away commits and
uncommitted work on the shared branch.

If you need to discard local changes, do it on a branch, or ask the user to run it.
MSG
  exit 2
fi

if has_verb push && { [ "$on_protected" = 1 ] || names_protected; }; then
  cat >&2 <<MSG
BLOCKED by master-guard: this command pushes to master/main (current branch:
"$branch").

Push the feature branch instead and open a merge/pull request:

  git push -u origin <your-branch>

If this really must be pushed to master, the user has to run it themselves.
MSG
  exit 2
fi

exit 0
