#!/usr/bin/env bash
# Verifies load-bearing literals survive in the agent and skill prompts.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
missing=0

# check <relative-file> <literal>...  (fixed-string match)
check() {
  local file="$1"
  shift
  local lit
  for lit in "$@"; do
    if ! grep -qF -- "$lit" "$root/$file"; then
      printf 'MISSING %s: %s\n' "$file" "$lit"
      missing=1
    fi
  done
}

skill=skills/custom-agent-plan/SKILL.md
check "$skill" \
  'name: custom-agent-plan' \
  '**🤖 Claude — <PR Description / Decision Needed / Plan / Plan Update / Progress / Deviation / Completion Summary / Follow-up Fix>**' \
  '**🤖 Claude — Progress (Follow-up round <n>)**' \
  '**🤖 Claude — Deviation**' \
  '**What was discovered:**' \
  '**Proposed change:**' \
  'Reply on this PR to say whether I should proceed with this change, take a different approach, or revert to the original plan.' \
  '**🤖 Claude — Follow-up Fix**' \
  '**What was found:**' \
  '**Proposed fix:**' \
  'PR #<n> open — planning starting.' \
  'Decision needed: PR #<n> — comment there.' \
  'Plan posted: PR #<n> — approve there to proceed.' \
  'Deviation posted: PR #<n> — reply there.' \
  'Done: PR #<n> ready for review.' \
  'Implement, Review, Push, Document, Verify' \
  '  - [ ] 1. <one-line label>' \
  '  - [ ] 6. Deviation: <one-line label>' \
  '~~...~~' \
  'Pass | Scope | Verdict | Blocking | Fix-in-PR | Follow-up | Fixed' \
  '../../scripts/tick-progress.sh <owner/repo> <id> <n>' \
  '../../scripts/tick-progress.sh --set-body {owner}/{repo} <id> /tmp/progress_body.md' \
  '../../scripts/tick-progress.sh --body {owner}/{repo} <id>' \
  '.claude/scripts/tick-progress.sh' \
  'literal path as the first word' \
  'no `cd ... &&`' \
  'no `bash` prefix' \
  '../../scripts/issue-meta.sh issue-types <owner>/<repo>' \
  '../../scripts/issue-meta.sh fields-get <owner>/<repo>' \
  '../../scripts/issue-meta.sh fields-set <owner>/<repo> <number> <fields.json>' \
  '.claude/scripts/issue-meta.sh' \
  '**Exit 0**' '**Exit 4**' '**Any other non-zero exit**' \
  '`$TMPDIR`' '64 KiB' \
  'Fail closed' \
  '`Small → Low`, `Medium → Medium`, `Large → High`' \
  'S=1, M=3, L=6' \
  '≤2 is Small, ≤6 is Medium, otherwise Large' \
  'Follow-ups from PR #N: <file|theme>' \
  'file:line — description (Type/Priority/Effort)' \
  'gh issue list --state open --search "in:title \"Follow-ups from PR #N: <file|theme>\""' \
  '`type: bug` (d73a4a)' '`type: task` (1d76db)' \
  '`priority: high` (b60205)' '`priority: medium` (fbca04)' \
  '`priority: low` (0e8a16)' \
  '`effort: small` (c2e0c6)' '`effort: medium` (fef2c0)' \
  '`effort: large` (f9d0c4)' \
  'gh label create "<name>" --color <hex> --force' \
  'gh issue edit <n> --add-label ... --remove-label ...' \
  'gh issue edit <n> --type Bug' \
  'gh pr create --draft --base <base> --title "..." --body-file /tmp/pr_body.md' \
  'gh pr create --draft --base <base branch> --title "<task summary>" --body-file /tmp/pr_body.md' \
  'gh pr comment <PR> --body-file <path>' \
  'gh pr edit <PR> --body-file <path>' \
  'gh pr view <PR> --json comments' \
  "cat > /tmp/pr_body.md <<'EOF'" \
  'fix/' 'feat/' 'chore/' 'docs/' 'test/' 'refactor/' \
  'no `claude/` prefix' \
  'git commit --allow-empty -m "<prefix>: start <task summary>"' \
  'git push -u origin <prefix>/<slug>' \
  '`EnterWorktree`' \
  '`action: "remove"`' \
  '`discard_changes: true`' \
  '.claude/worktrees/' \
  '`autoMemoryEnabled: false`' \
  'rm -r .claude/agent-memory' \
  'git status' 'git log @{u}..' 'ScheduleWakeup' \
  '## 📋 Project Orchestrator — Plan Mode' \
  'Current Roadmap Position' \
  'Prerequisites Check' \
  '## Wait gate' \
  '**Never take the PR out of draft yourself.**' \
  '`action: "remove"` (never `"keep"`)'

# The false hook claim and the old --body forms must stay gone.
for bad in 'plans/`or' '--body "..."' 'the hook denies'; do
  if grep -qF -- "$bad" "$root/$skill"; then
    printf 'UNEXPECTED %s: %s\n' "$skill" "$bad"
    missing=1
  fi
done

check agents/code-reviewer.md \
  '## Code Review — PASS' \
  '## Code Review — NEEDS_REVISION' \
  '### Mechanical gates' \
  '- ruff: ✅ zero violations' \
  '- pyright: ✅ zero errors, strict mode' \
  '### Correctness' '### Security' '### Style gate' \
  '### Test adequacy' '### Domain invariants' \
  '### Blocking Findings' \
  '### Fix-in-PR (fix in this PR'"'"'s revision)' \
  '### Follow-up Findings (non-blocking — file as grouped issues)' \
  '### Follow-up Findings (non-blocking — file as grouped issues, do not fix in this revision pass)' \
  '### Decision Needed (ask the user: fix now, or defer?)' \
  '### Late findings (re-review passes only — file as grouped issues)' \
  '### Already confirmed clean' \
  'n/a — pass 1' \
  '**Type:** Bug|Task · **Priority:** High|Medium|Low · **Effort:** Small|Medium|Large' \
  'Correctness`, `Security`, `Style`, `Tests`, `Domain invariant`, `Mechanical (lint)`, `Mechanical (typecheck)`'

check agents/project-orchestrator.md \
  '## 📋 Project Orchestrator — Plan Mode' \
  '## 📋 Project Orchestrator — Verify Mode' \
  '## 📋 Project Orchestrator — Coordination Mode' \
  '### ⚖️ Decision Needed' \
  '**Question for the user:**' \
  '### ✅ Completed as Planned' \
  '### ⚠️ Deviations / Gaps' \
  '### 📝 plans/OPEN_WORK.md Updates Made' \
  '### 🔜 Next Recommended Step' \
  '### 💬 Suggested Commit Message' \
  '### Gate Status' \
  'PASS / BLOCKED / WAITING' \
  'Review passes: [n/4 (this round)]' \
  'OPEN' 'IN PROGRESS' 'BLOCKED (owner)' 'DEFERRED' \
  '**Scope rule.**'

check agents/technical-writer.md \
  '## Technical Writer — Documentation Update' \
  '### Changes made' \
  '### CLAUDE.md / plans/ flag (if any)' \
  '[ABC-123](https://<org>.atlassian.net/browse/ABC-123)' \
  'Jira base URL:' \
  '$`' \
  '```math' \
  '  ```math' \
  'Always start the fence at column 0'

check agents/web-researcher.md \
  '1. **Answers**' '2. **Findings**' '3. **Conflicts**' '4. **Gaps**' \
  'stated' 'inferred'

# Do-NOT-use routing clauses in descriptions.
check agents/junior-engineer.md 'Do NOT use it for web research (use web-researcher)'
check agents/code-reviewer.md 'Do NOT use for implementation work, documentation updates, or roadmap management'
check agents/technical-writer.md 'Does NOT touch source code, tests, or plan files'
check agents/web-researcher.md 'Do NOT use it for reading or summarizing this repo'
check agents/senior-engineer.md 'Do NOT use it for larger web research (use web-researcher)'

# Frontmatter: name matches filename; tools/model/effort present.
for f in "$root"/agents/*.md; do
  stem="$(basename "$f" .md)"
  fm="$(awk 'NR==1&&/^---$/{n=1;next} n&&/^---$/{exit} n' "$f")"
  if ! grep -qE "^name: \"?${stem}\"?\$" <<<"$fm"; then
    printf 'MISSING agents/%s.md: frontmatter name matching "%s"\n' "$stem" "$stem"
    missing=1
  fi
  # technical-writer has no `effort:` line by design (frontmatter is fixed).
  keys='tools model effort color'
  [ "$stem" = technical-writer ] && keys='tools model color'
  for key in $keys; do
    if ! grep -q "^${key}:" <<<"$fm"; then
      printf 'MISSING agents/%s.md: frontmatter %s:\n' "$stem" "$key"
      missing=1
    fi
  done
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi
echo 'OK: all prompt invariants present'
