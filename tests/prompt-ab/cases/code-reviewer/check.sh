#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

check verdict-needs-revision "no NEEDS_REVISION heading" result_has '^## Code Review — NEEDS_REVISION'

if section 'Blocking Findings' | grep -Eiq 'F401|unused import|imported but unused|import os'; then
  pass ruff-blocking
else fail ruff-blocking "unused import not in Blocking section"; fi

# One finding line must name char_count with the defect (replace/whitespace/spaces/docstring)
# or cite core.py at the bug's line (23-25 after the patch).
if { section 'Blocking Findings'; section 'Fix-in-PR'; } | grep -Ei '\bchar_count\b' |
  grep -Eiq '\breplace\b|\bwhitespace\b|\bspaces?\b|\bdocstring\b|core\.py:2[345]\b' ||
  { section 'Blocking Findings'; section 'Fix-in-PR'; } | grep -Eiq 'core\.py:2[345]\b'; then
  pass bug-found
else fail bug-found "char_count bug not in Blocking/Fix-in-PR"; fi

# Cheap in-file issue: the new --chars flag has no help text.
if section 'Fix-in-PR' | grep -Ei -- '--chars|\bchars flag\b' |
  grep -Eiq '\bhelp\b'; then
  pass cheap-fix-in-pr
else fail cheap-fix-in-pr "--chars missing help text not under Fix-in-PR"; fi

# Pre-existing weakness (top_words keeps punctuation attached) belongs in Follow-up, not Blocking.
if section 'Follow-up Findings' | grep -Eiq 'top_words|punctuation' &&
  ! section 'Blocking Findings' | grep -Eiq 'top_words|punctuation'; then
  pass preexisting-follow-up
else fail preexisting-follow-up "top_words/punctuation weakness not under Follow-up (or is under Blocking)"; fi

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
