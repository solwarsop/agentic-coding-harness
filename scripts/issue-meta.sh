#!/usr/bin/env bash
# Issue Types / issue-field lookups and writes for the issue classification convention.
# Usage: ../../scripts/issue-meta.sh issue-types <owner/repo>   (JSON: repository.issueTypes.nodes[].name; empty/null = not enabled)
#        ../../scripts/issue-meta.sh fields-get <owner/repo> <issue-number>   (print issue field values; exit 4 on HTTP 404 = fields not enabled)
#        ../../scripts/issue-meta.sh fields-set <owner/repo> <issue-number> <json-file>   (POST the file as the payload; file under ${TMPDIR:-/tmp}, <= 64 KiB)
# The path above is from the task worktree root (<project>/.claude/worktrees/<name>); from the project root use .claude/scripts/issue-meta.sh.
# Other gh failures propagate gh's stderr and exit code (gh's own 4 is remapped to 1).
set -euo pipefail

usage() { echo "usage: $0 issue-types <owner/repo> | fields-get <owner/repo> <issue-number> | fields-set <owner/repo> <issue-number> <json-file>" >&2; exit 2; }
valid_repo() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
  [[ "${1%/*}" =~ ^\.+$ || "${1#*/}" =~ ^\.+$ ]] && return 1
  return 0
}
valid_num() { [[ "$1" =~ ^[0-9]+$ ]]; }
# Sets file_abs to the resolved path of $1 if it is a regular, readable file <= 64 KiB under ${TMPDIR:-/tmp}; else exits 2.
check_file() {
  local tmp
  tmp=$(realpath -e -- "${TMPDIR:-/tmp}" 2>/dev/null) || { echo "error: cannot resolve ${TMPDIR:-/tmp}" >&2; exit 2; }
  file_abs=$(realpath -e -- "$1" 2>/dev/null) || { echo "error: file not found: $1" >&2; exit 2; }
  [ -f "$file_abs" ] && [ -r "$file_abs" ] || { echo "error: not a readable regular file: $1" >&2; exit 2; }
  case $file_abs in "${tmp%/}"/*) ;; *) echo "error: file must be under ${tmp%/}/ (resolved: $file_abs)" >&2; exit 2 ;; esac
  [ "$(wc -c < "$file_abs")" -le 65536 ] || { echo "error: file exceeds 65536 bytes: $1" >&2; exit 2; }
}

mode=${1:-}
case $mode in
  issue-types)
    [ "$#" -eq 2 ] && valid_repo "$2" || usage
    gh api graphql \
      -f query='query($owner:String!,$name:String!){ repository(owner:$owner, name:$name) { issueTypes(first:10) { nodes { name } } } }' \
      -f owner="${2%/*}" -f name="${2#*/}"
    ;;
  fields-get)
    [ "$#" -eq 3 ] && valid_repo "$2" && valid_num "$3" || usage
    err=$(mktemp)
    trap 'rm -f "$err"' EXIT
    rc=0
    gh api "repos/$2/issues/$3/issue-field-values" 2> "$err" || rc=$?
    [ -s "$err" ] && cat "$err" >&2
    if [ "$rc" -ne 0 ]; then
      if grep -q 'HTTP 404' "$err"; then
        echo "issue fields not enabled (HTTP 404)" >&2
        exit 4
      fi
      [ "$rc" -eq 4 ] && rc=1 # gh's own exit 4 (auth) must not read as "not enabled"
      exit "$rc"
    fi
    ;;
  fields-set)
    [ "$#" -eq 4 ] && valid_repo "$2" && valid_num "$3" || usage
    check_file "$4"
    gh api --method POST "repos/$2/issues/$3/issue-field-values" --input "$file_abs"
    ;;
  *) usage ;;
esac
