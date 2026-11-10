#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

check plan-heading "no Plan Mode heading" result_has '^## 📋 Project Orchestrator — Plan Mode'

missing=""
for h in 'Testing Scope' 'Agent Assignments' 'Success Criteria'; do
  grep -qF -- "### $h" "$RESULT_TEXT" || missing+="$h; "
done
if [[ -z "$missing" ]]; then pass sections; else fail sections "missing: $missing"; fi

direct=$(tool_uses | jq -r 'select(.name == "Read" or .name == "Grep" or .name == "Glob")
  | (.input.file_path // .input.path // .input.pattern // "") | select(test("textstats/|tests/|\\.py$"))' | head -3)
if [[ -z "$direct" ]]; then pass no-direct-source-read; else fail no-direct-source-read "$(tr '\n' ' ' <<<"$direct")"; fi

check assigns-senior-engineer "senior-engineer not named in assignments" \
  bash -c "grep -A40 -F '### Agent Assignments' '$RESULT_TEXT' | grep -qi 'senior-engineer'"

check no-decision-needed "Decision Needed heading present" \
  bash -c "! grep -Eq '^### (⚖️ )?Decision Needed' '$RESULT_TEXT'"
