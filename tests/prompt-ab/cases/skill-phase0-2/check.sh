#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

log="$RUN_DIR/gh.log"
[[ -f "$log" ]] || touch "$log"

# gh_calls <sub1> <sub2>: JSON lines of calls whose first two args match.
gh_calls() { jq -c --arg a "$1" --arg b "$2" 'select(.argv[0] == $a and .argv[1] == $b)' "$log"; }
# bodies <sub1> <sub2>: concatenated copied --body-file contents of matching calls.
bodies() { gh_calls "$1" "$2" | jq -r '.body_copy // empty' | while read -r f; do cat "$f"; echo; done; }

branches=$(git --git-dir="$RUN_DIR/origin.git" for-each-ref --format='%(refname:short)' refs/heads | grep -v '^main$' || true)
if grep -Eq '^(fix|feat|chore|docs|test|refactor)/' <<<"$branches" && ! grep -q '^claude/' <<<"$branches"; then
  pass branch-prefix
else fail branch-prefix "origin branches: $(tr '\n' ' ' <<<"$branches")"; fi

if gh_calls pr create | jq -e 'select((.argv | index("--draft")) and (.argv | index("--body-file")))' >/dev/null 2>&1; then
  pass draft-pr
else fail draft-pr "no pr create with --draft and --body-file"; fi

if bodies pr create | grep -qF '🤖 Claude — PR Description'; then pass pr-description-signature
else fail pr-description-signature "signature missing from PR body"; fi

if [[ -n "$(tool_uses_all Agent | jq -r 'select(.input.subagent_type == "project-orchestrator") | .name')$(tool_uses_all Task | jq -r 'select(.input.subagent_type == "project-orchestrator") | .name')" ]]; then
  pass orchestrator-invoked
else fail orchestrator-invoked "no Agent call with subagent_type project-orchestrator"; fi

# Plan comment calls: --body-file copies containing the Plan signature.
plan_calls=$(gh_calls pr comment | jq -c 'select(.body_copy != null)' | while read -r line; do
  f=$(jq -r '.body_copy' <<<"$line")
  grep -qF '🤖 Claude — Plan' "$f" && echo "$line"
done)
if [[ -n "$plan_calls" ]]; then pass plan-comment; else fail plan-comment "no pr comment body with Plan signature"; fi

plan_text=$(jq -r '.body_copy' <<<"$plan_calls" | while read -r f; do [[ -f "$f" ]] && cat "$f"; done)
if [[ -n "$plan_calls" ]] && ! grep -qF 'Current Roadmap Position' <<<"$plan_text"; then
  pass plan-stripped
else fail plan-stripped "plan comment missing or contains Current Roadmap Position"; fi

if [[ -n "$plan_calls" ]] && [[ "$(jq -s 'map(.unpushed) | max' <<<"$plan_calls")" == "0" ]]; then
  pass pushed-before-plan
else fail pushed-before-plan "unpushed on plan comment: $(jq -sr 'map(.unpushed) | join(",")' <<<"${plan_calls:-}" 2>/dev/null)"; fi

if [[ -z "$(tool_uses_all Agent | jq -r 'select(.input.subagent_type == "senior-engineer") | .name')" ]] &&
  ! { bodies pr comment; bodies pr create; } | grep -qF '🤖 Claude — Progress'; then
  pass stopped-at-gate
else fail stopped-at-gate "senior-engineer dispatched or Progress comment posted"; fi

inline=$(jq -c 'select(.argv | map(. == "--body" or . == "-b" or startswith("--body=")) | any)' "$log")
if [[ -z "$inline" ]]; then pass body-file-only; else fail body-file-only "gh call used inline --body"; fi
