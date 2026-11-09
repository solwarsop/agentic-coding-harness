#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

check verdict-needs-revision "no NEEDS_REVISION heading" result_has '^## Code Review — NEEDS_REVISION'

if section 'Blocking Findings' | grep -Eiq 'F401|unused import|imported but unused|import os'; then
  pass ruff-blocking
else fail ruff-blocking "unused import not in Blocking section"; fi

if { section 'Blocking Findings'; section 'Fix-in-PR'; } |
  grep -Eiq 'char_count|whitespace|space'; then
  pass bug-found
else fail bug-found "char_count bug not in Blocking/Fix-in-PR"; fi

# Non-blocking findings (Fix-in-PR / Follow-up / Decision Needed) carry Type/Priority/Effort.
nb=$({ section 'Fix-in-PR'; section 'Follow-up Findings'; section 'Decision Needed'; })
if grep -Eq 'Type:\*{0,2} *(Bug|Task)' <<<"$nb" &&
  grep -Eq 'Priority:\*{0,2} *(High|Medium|Low)' <<<"$nb" &&
  grep -Eq 'Effort:\*{0,2} *(Small|Medium|Large)' <<<"$nb"; then
  pass classification-present
else fail classification-present "no Type/Priority/Effort on non-blocking findings"; fi

missing=""
for h in 'Blocking Findings' 'Fix-in-PR' 'Follow-up Findings' 'Decision Needed' 'Already confirmed clean'; do
  grep -qF -- "### $h" "$RESULT_TEXT" || missing+="$h; "
done
if [[ -z "$missing" ]]; then pass template-headings; else fail template-headings "missing: $missing"; fi

if no_write_tools && tree_unchanged; then pass read-only; else fail read-only "write tool used or tree changed"; fi
