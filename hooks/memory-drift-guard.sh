#!/usr/bin/env bash
# PreToolUse guard for Bash.
#
# Blocks a `git commit` that changes code covered by a note in .agents/memory/
# when that note is not part of the same commit, so the note is reviewed while
# the diff is still fresh. A note declares what it covers with the same `paths:`
# frontmatter that rules/ uses; a note without it is never demanded. When the
# note is still accurate, re-run with SKIP_MEMORY_CHECK=1 in front of the command.
#
# Fails OPEN: any internal error exits 0 so the session is never wedged.
set -uo pipefail

payload="$(cat)" || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -z "$cmd" ] && exit 0

# Same matcher as master-guard.sh: only global options between `git` and the verb.
has_verb() {
  printf '%s' "$cmd" | grep -Eq \
    "(^|[^[:alnum:]_-])git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+$1([[:space:]]|\$)"
}

has_verb commit || exit 0
printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])SKIP_MEMORY_CHECK=1[[:space:]]' && exit 0

# `git -C <dir>` commits in another repo, so its notes and index are the ones that
# count. Same block master-guard uses — see the note there on what it does not cover.
for d in $(printf '%s' "$cmd" | grep -Eo -- '-C[[:space:]]+[^[:space:];&|]+' | sed -E 's/^-C[[:space:]]+//'); do
  cd "$d" 2>/dev/null || exit 0
done

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
files="$(git diff --cached --name-only 2>/dev/null)" || exit 0
# `git add ... && git commit` and `commit -a` stage only after this hook runs.
# ponytail: tracked changes only, a brand-new file added in the same chain is missed.
if has_verb add || printf '%s' "$cmd" | grep -Eq -- '[[:space:]](-[[:alnum:]]*a[[:alnum:]]*|--all)([[:space:]]|$)'; then
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
