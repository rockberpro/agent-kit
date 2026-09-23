#!/usr/bin/env bash
# PreToolUse guard for Bash. Three checks, each blocks with exit 2:
#
#   master-guard        while HEAD is on master/main, blocks anything that writes a commit
#                       there (`commit`, `cherry-pick`, `revert`, `am`, `rebase`), plus
#                       `git merge` and `git reset --hard`; blocks any `git push` that
#                       targets master/main (by being on it or naming it in the refspec).
#   secret-guard        blocks a `git commit` that adds an obvious secret: a private-key
#                       header, a well-known token format, a `.env`/keystore file.
#   memory-drift-guard  blocks a `git commit` that changes code covered by a note in
#                       .agents/memory/ (its `paths:` frontmatter) when the note is not
#                       in the same commit. SKIP_MEMORY_CHECK=1 in front when it still holds.
#
# Fails OPEN: any internal error exits 0 so the session is never wedged.
set -uo pipefail

payload="$(cat)" || exit 0
# perl + JSON::PP, not jq: it ships with git on Windows (Git Bash) and Linux alike.
# Decode errors are eval-caught (fail open); a nonzero exit means the parser itself is
# missing, which is a setup problem: exit 1 so Claude Code shows it instead of hiding it.
cmd="$(printf '%s' "$payload" | perl -MJSON::PP -0777 -ne 'binmode STDOUT, ":utf8"; my $c = eval { decode_json($_)->{tool_input}{command} }; print $c if defined $c && !ref $c' 2>/dev/null)" \
  || { echo "agent-kit guard: perl with JSON::PP not found, so this guard is NOT running. Install perl (it ships with git)." >&2; exit 1; }
[ -z "$cmd" ] && exit 0

# Match `git [global options] <verb>` (handles `git -C x commit`, `&&` chains).
# Only global options may sit between `git` and the verb, so `git log --grep commit`
# and `echo "git commitment"` do not trip it.
has_verb() {
  printf '%s' "$cmd" | grep -Eq \
    "(^|[^[:alnum:]_-])git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+$1([[:space:]]|\$)"
}

# `git -C <dir>` acts on another repo, so branch, index and notes are read there and not
# in cwd. This process is disposable, so just move: every git call below follows. Each
# -C is relative to the previous one, hence the loop.
# ponytail: one git invocation per call assumed; in `git -C a x && git -C b y` the
# dirs stack. Paths with spaces are not matched. Both fail open, never block wrongly.
for d in $(printf '%s' "$cmd" | grep -Eo -- '-C[[:space:]]+[^[:space:];&|]+' | sed -E 's/^-C[[:space:]]+//'); do
  cd "$d" 2>/dev/null || exit 0
done

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0

# A short-flag cluster containing `a` (-a, -am, -ma...) or --all: `commit -a` stages
# tracked changes only after this hook runs.
commit_all() { printf '%s' "$cmd" | grep -Eq -- '(^|[[:space:]])(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'; }

# ---- master-guard -----------------------------------------------------------------------
case "$branch" in
  master|main) on_protected=1 ;;
  *)           on_protected=0 ;;
esac

# `git switch -c x && git commit` runs the commit on the new branch, but this hook only
# sees the branch as it is now. Only `&&` counts (with `;` a failed switch still
# commits), and only when nothing before it already writes to master/main.
# ponytail: new branches only; `git switch existing && git commit` still blocks.
new_branch='git[[:space:]]+(switch[[:space:]]+(-c|-C|--create|--force-create)|checkout[[:space:]]+-[bB])[[:space:]]+[^;&|]*&&'
if [ "$on_protected" = 1 ] && [[ $cmd =~ $new_branch ]]; then
  before="${cmd%%"${BASH_REMATCH[0]}"*}"
  (cmd="$before"; has_verb commit || has_verb cherry-pick || has_verb revert || has_verb am \
    || has_verb rebase || has_verb merge || has_verb reset || has_verb push) || on_protected=0
fi

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

# The other two only look at commits.
has_verb commit || exit 0

# ---- secret-guard -----------------------------------------------------------------------
# A secret that lands in a commit is leaked (it survives in history even if a later commit
# removes it), so the gate is the commit, not the push. Scans only ADDED lines, so a secret
# already in history does not block unrelated commits. Named-format tokens only, no
# entropy heuristics, to keep false positives near zero.

# `commit -a` commits tracked modifications not yet in the index: diff against HEAD.
# Over-detecting is safe here: HEAD is a superset of --cached.
if commit_all; then range=(HEAD); else range=(--cached); fi

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

if [ -n "$env_hit$key_hit$tok_hit" ]; then
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
fi

# ---- memory-drift-guard -----------------------------------------------------------------
printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])SKIP_MEMORY_CHECK=1[[:space:]]' && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
files="$(git diff --cached --name-only 2>/dev/null)" || exit 0
# `git add ... && git commit` and `commit -a` stage only after this hook runs.
# ponytail: tracked changes only, a brand-new file added in the same chain is missed.
if has_verb add || commit_all; then
  files="$(printf '%s\n%s' "$files" "$(git diff HEAD --name-only 2>/dev/null)")"
fi
files="$(printf '%s\n' "$files" | sed '/^$/d' | sort -u)"
[ -z "$files" ] && exit 0

# The `paths:` list of a note's frontmatter, one glob per line.
note_paths() {
  awk 'NR == 1 { if ($0 != "---") exit; next }
       $0 == "---" { exit }
       /^paths:/ { p = 1; next }
       p && /^[[:space:]]*-/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/^["\047]|["\047][[:space:]]*$/, ""); print; next }
       /^[^[:space:]]/ { p = 0 }' "$1"
}

# Bash `*` already crosses `/`; a leading `**/` must also match at the root.
matches() {
  [[ $1 == $2 ]] || { [[ $2 == '**/'* ]] && [[ $1 == ${2#'**/'} ]]; }
}

missing="$(
  for note in "$root"/.agents/memory/*.md; do
    [ -f "$note" ] || continue
    rel=".agents/memory/${note##*/}"
    printf '%s\n' "$files" | grep -Fxq "$rel" && continue
    globs="$(note_paths "$note")"
    [ -n "$globs" ] || continue
    while IFS= read -r f; do
      while IFS= read -r g; do
        matches "$f" "$g" && { printf '  %s  <- %s\n' "$rel" "$f"; continue 3; }
      done <<< "$globs"
    done <<< "$files"
  done
)"
[ -z "$missing" ] && exit 0

cat >&2 <<MSG
BLOCKED by memory-drift-guard: this commit changes code covered by memory notes
that are not part of the commit:

$missing

Read each note against the diff and fix whatever the change made wrong or
incomplete, then stage it with the code. If the note is still accurate, re-run
the same command prefixed with SKIP_MEMORY_CHECK=1.
MSG
exit 2
