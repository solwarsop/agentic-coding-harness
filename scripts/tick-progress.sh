#!/usr/bin/env bash
# Tick plan sub-step <N> ("  - [ ] <N>. ...") in a Progress PR comment.
# Usage: tick-progress.sh <owner/repo> <comment-id> <step-number>
#        tick-progress.sh --transform-only <step-number>   (body on stdin, result on stdout; no network)
set -euo pipefail

# Prints the body with step $1 ticked. Exit 3 if the step line is missing.
transform() {
  awk -v n="$1" '
    BEGIN { pat = "^[ \t]+- \\[[ x]\\] " n "\\.( |$)" }
    $0 ~ pat { found = 1; sub(/\[ \]/, "[x]") }
    { print }
    END { if (!found) exit 3 }
  '
}

if [ "${1:-}" = "--transform-only" ]; then
  [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "usage: $0 --transform-only <step-number>" >&2; exit 2; }
  transform "$2"
  exit
fi

if [ "$#" -ne 3 ] || ! [[ "$3" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 <owner/repo> <comment-id> <step-number>" >&2
  exit 2
fi
repo=$1
id=$2
step=$3

old=$(mktemp)
new=$(mktemp)
trap 'rm -f "$old" "$new"' EXIT

gh api "repos/$repo/issues/comments/$id" --jq .body > "$old"
rc=0
transform "$step" < "$old" > "$new" || rc=$?
if [ "$rc" -eq 3 ]; then
  echo "error: no sub-step line '  - [ ] $step. ...' in comment $id" >&2
  exit 1
elif [ "$rc" -ne 0 ]; then
  exit "$rc"
fi
if cmp -s "$old" "$new"; then
  echo "step $step already ticked"
  exit 0
fi
gh api --method PATCH "repos/$repo/issues/comments/$id" -F body=@"$new" > /dev/null
echo "ticked step $step"
