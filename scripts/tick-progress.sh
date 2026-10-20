#!/usr/bin/env bash
# Read, replace or tick plan sub-steps ("  - [ ] <N>. ..." under Implement) in a Progress PR comment; GET-then-PATCH is last-writer-wins.
# Usage: ../../scripts/tick-progress.sh <owner/repo> <comment-id> <step-number>
#        ../../scripts/tick-progress.sh --body <owner/repo> <comment-id>   (print the current comment body)
#        ../../scripts/tick-progress.sh --set-body <owner/repo> <comment-id> <file>   (replace the comment body with the file's content)
#        ../../scripts/tick-progress.sh --transform-only <step-number>   (body on stdin, result on stdout; no network)
# The path above is from the task worktree root (<project>/.claude/worktrees/<name>); from the project root use .claude/scripts/tick-progress.sh.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib-gh-helpers.sh"

# Prints the body with step $1 ticked: the first matching sub-step line between
# the top-level Implement line and the next top-level box. Exit 3 if missing.
transform() {
  awk -v n="$1" '
    BEGIN { pat = "^[ \t]+- \\[[ x]\\] " n "\\.( |$)" }
    /^- \[[ x]\] Implement/ { sec = 1 }
    !/^- \[[ x]\] Implement/ && /^- \[/ { sec = 0 }
    sec && !found && $0 ~ pat { found = 1; if (match($0, /^[ \t]+- \[ \]/)) $0 = substr($0, 1, RLENGTH - 2) "x]" substr($0, RLENGTH + 1) }
    { print }
    END { if (!found) exit 3 }
  '
}

usage() { echo "usage: $0 <owner/repo> <comment-id> <step-number> | --body <owner/repo> <comment-id> | --set-body <owner/repo> <comment-id> <file> | --transform-only <step-number>" >&2; exit 2; }

if [ "${1:-}" = "--transform-only" ]; then
  [ "$#" -eq 2 ] && valid_num "$2" || usage
  transform "$2"
  exit
fi

if [ "${1:-}" = "--body" ]; then
  [ "$#" -eq 3 ] && valid_repo "$2" && valid_num "$3" || usage
  gh api "repos/$2/issues/comments/$3" --jq .body
  exit
fi

if [ "${1:-}" = "--set-body" ]; then
  [ "$#" -eq 4 ] && valid_repo "$2" && valid_num "$3" || usage
  check_payload_file "body file" "$4"; body_abs=$payload_abs
  gh api --method PATCH "repos/$2/issues/comments/$3" -F body=@"$body_abs" > /dev/null
  echo "updated comment $3"
  exit
fi

[ "$#" -eq 3 ] && valid_repo "$1" && valid_num "$2" && valid_num "$3" || usage
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
