#!/usr/bin/env bash
# Shared helpers for case check.sh scripts. Source this file.
# Expects env: TRANSCRIPT (stream-json file), RESULT_TEXT (final result text file),
# RUN_DIR, CASE_DIR. cwd is the scratch fixture copy.

# pass <id> / fail <id> [detail]: emit one scored line.
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s %s\n' "$1" "${2:-}"; }

# check <id> <detail> <command...>: pass if the command succeeds, else fail with detail.
check() {
  local id="$1" detail="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then pass "$id"; else fail "$id" "$detail"; fi
}

# tool_uses [name]: one compact JSON object {name,input} per top-level tool_use
# (subagent calls, which carry parent_tool_use_id, are excluded).
tool_uses() { _tool_uses_filtered 'select((.parent_tool_use_id // null) == null)' "${1:-}"; }

# tool_uses_all [name]: same, including calls made by subagents.
tool_uses_all() { _tool_uses_filtered '.' "${1:-}"; }

_tool_uses_filtered() {
  jq -c --arg n "$2" "$1"' | select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use") | select($n == "" or .name == $n) | {name, input}' \
    "$TRANSCRIPT" 2>/dev/null
}

# result_has <ERE>: final result text matches the regex (case-sensitive).
result_has() { grep -Eq -- "$1" "$RESULT_TEXT"; }

# result_has_i <ERE>: case-insensitive variant.
result_has_i() { grep -Eiq -- "$1" "$RESULT_TEXT"; }

# section <heading-prefix>: print the body of the '### <prefix>...' section of the result
# (up to the next '#'/'##'/'###' heading).
section() {
  awk -v p="### $1" '
    index($0, p) == 1 { on = 1; next }
    on && /^#{1,3} / { on = 0 }
    on { print }
  ' "$RESULT_TEXT"
}

# tree_unchanged: `git status --porcelain` equals the post-setup snapshot.
tree_unchanged() {
  [[ "$(git status --porcelain)" == "$(cat "$RUN_DIR/raw/status-before.txt")" ]]
}

# No Edit/Write/NotebookEdit tool_use (top-level or subagent).
no_write_tools() { [[ -z "$(tool_uses_all Edit)$(tool_uses_all Write)$(tool_uses_all NotebookEdit)" ]]; }

# python_ok <code>: run python -I -c with the scratch tree on sys.path.
python_ok() { PYTHONPATH=. python3 -c "$1"; }
