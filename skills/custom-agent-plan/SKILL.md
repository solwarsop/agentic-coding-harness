---
name: custom-agent-plan
description: "Full planning and implementation workflow: a branch + draft PR opened at the start of every task, orchestrator-led planning with Haiku-based codebase summarization, a PR-comment decision gate when the plan hinges on a genuine approach trade-off (e.g. proof-of-concept vs. production-ready), a PR-comment approval gate before execution (including the plan's testing scope, since new unit tests default to a follow-up task rather than assumed scope), PR-comment deviation confirmation during implementation, severity-tiered code review where only functionality-blocking or critical findings pause the loop, GitHub issues filed for non-blocking findings always classified with a mandatory Type (Bug/Task), Priority, and Effort estimate, and a post-completion follow-up phase that routes any issue found after wrap-up (PR comment or the agent's own later testing) back through the same senior-engineer/code-reviewer loop instead of being patched inline."
---

Run the planning and implementation workflow for the user's task. Follow these phases in order and do not skip the approval gate. The guiding principle: **this repo's PR history is the permanent record of what Claude proposed and what the user approved** — every plan, revision, and deviation gets posted as a signed PR comment, not just said in chat.

## Signing convention

Every comment, and the PR description itself, must open with an unambiguous signature line so nothing posted by this workflow is ever mistaken for human-authored content — including while the PR is still a draft:

```
**🤖 Claude — <PR Description / Decision Needed / Plan / Plan Update / Deviation / Completion Summary / Follow-up Fix>**

<content>
```

## Worktree convention

This coordinating session works in a single disposable worktree for the whole task, rather than directly in the shared working directory — every subagent it dispatches (`project-orchestrator`, `junior-engineer`, `senior-engineer`, `code-reviewer`, `technical-writer`) inherits that same working directory when invoked, so only this session manages the worktree itself; the subagents don't each need their own.

1. At the start of the task (Phase 0), call `EnterWorktree` with no `name`/`path` (let it generate one) to get a fresh worktree. **Never try to detect, reuse, repair, or clean up an existing or conflicting worktree left by another session** — ignore whatever else is already on disk under `.claude/worktrees/` and let `EnterWorktree` create its own alongside it.
2. Create and push the task's branch inside that worktree (Phase 0 below) — every later phase, and every subagent dispatched from this session, works on that same branch in that same worktree for as long as the task stays open.
3. Once Phase 4's Completion Summary is posted, call `ExitWorktree` with `action: "remove"` (never `"keep"`) so nothing is left behind. If a Phase 5 follow-up round arrives later — possibly much later — treat it as its own fresh session: call `EnterWorktree` again at the start of that round, do the work, and `ExitWorktree action: "remove"` again once it's pushed.

## GitHub issue classification convention

Every GitHub issue filed by this workflow (Phase 3 step 2's Follow-up findings, Phase 3 step 2's deferred Decision Needed findings, and Phase 5 step 4's equivalents) must carry all three classifications below — **never file one unclassified.** `code-reviewer` already attaches a Type/Priority/Effort tag to every Follow-up and Decision Needed finding it reports; use those tags verbatim rather than re-deriving them.

- **Type** — prefer this repo's native GitHub Issue Types if enabled. Check once per task:
  ```
  gh api graphql -f query='query { repository(owner:"<owner>", name:"<repo>") { issueTypes(first:10) { nodes { name } } } }'
  ```
  A non-empty `issueTypes` list means native types are available — pass `--type Bug` or `--type Task` to `gh issue create` (matching the finding's Type tag). An empty/null list (common on personal-account repos, and orgs that haven't enabled the feature) means fall back to a `type: bug` / `type: task` label instead — create it first if missing: `gh label create "type: bug" --color d73a4a --force` / `gh label create "type: task" --color 1d76db --force` (`--force` is idempotent, safe even if the label already exists).
- **Priority** — a `priority: high` / `priority: medium` / `priority: low` label, taken from the finding's Priority tag. Ensure the labels exist first: `gh label create "priority: high" --color b60205 --force`, `gh label create "priority: medium" --color fbca04 --force`, `gh label create "priority: low" --color 0e8a16 --force`.
- **Effort** — an `effort: small` / `effort: medium` / `effort: large` label, taken from the finding's Effort tag. Ensure the labels exist first: `gh label create "effort: small" --color c2e0c6 --force`, `gh label create "effort: medium" --color fef2c0 --force`, `gh label create "effort: large" --color f9d0c4 --force`.

Example, on a repo with native Issue Types enabled:
```
gh issue create --title "..." --body "..." --type Bug --label "priority: high" --label "effort: small"
```
Example, on a repo without native Issue Types:
```
gh issue create --title "..." --body "..." --label "type: bug" --label "priority: high" --label "effort: small"
```

## Phase 0: Start work — branch, push, draft PR

Before any planning happens:

0. Call `EnterWorktree` per the Worktree convention above — this session works in that one worktree for the rest of the task, so set it up before touching git.
1. Determine the base branch and protected/deploy branch for this task:
   - **Base branch**: default to the repository's actual default branch (check `git remote show origin` or `gh repo view --json defaultBranchRef`), unless the user or `CLAUDE.md` names a different integration branch (e.g. a `staging`/`develop` branch used ahead of a protected `main`/`production` branch). Use whatever base you land on consistently through every step below and for the rest of the workflow.
   - **Deploy-triggering branch**: check `CLAUDE.md` and any CI/CD workflow files (e.g. `.github/workflows/*.yml`) for a branch that triggers a production deploy on push/merge. Agent-originated PRs must never target that branch directly unless the user explicitly asks for it — target the integration/base branch instead.
2. Run `git status` and confirm the working tree is clean relative to that base branch (should already be clean in a fresh worktree, but confirm rather than assume — never branch off uncommitted work that isn't yours).
3. Create a branch off the base branch, named `<prefix>/<short-kebab-slug-of-the-task>` — **no `claude/` prefix.** Pick the conventional prefix that matches the task, same vocabulary as this repo's commit messages: `fix/` for a bug fix, `feat/` for new functionality, `chore/` for tooling/maintenance, `docs/` for documentation-only work, `test/` for test-only additions, `refactor/` for a behavior-preserving restructure. When an issue number is available, fold it into the slug (e.g. `fix/early-stopping-patience-34`).
4. GitHub won't open a PR from a branch with no commits ahead of base, so create an empty commit to seed it: `git commit --allow-empty -m "<prefix>: start <task summary>"` (same prefix as the branch name).
5. Push with `-u`: `git push -u origin <prefix>/<slug>`.
6. Open a **draft** PR whose body opens with the **PR Description** signature (see Signing convention below): `gh pr create --draft --base <base branch> --title "<task summary>" --body "$(printf '**🤖 Claude — PR Description**\n\n<one-line description of what this PR will contain; note that the plan, approvals, and any deviations will follow as comments below>')"`.
7. Note the PR number/URL and the base branch used — every later phase posts comments to this same PR.

Tell the user, in one line: `PR #<n> open — planning starting.`

## Phase 1: Orchestrator planning

Invoke `project-orchestrator` in Plan Mode with the user's task description. The orchestrator will:
- Read `plans/OPEN_WORK.md` — the rolling list of open work and the default home for a new item (standalone plan documents are also allowed in `plans/` for larger, multi-phase efforts, pointed to from `OPEN_WORK.md`) — and confirm this is the correct next step
- Check prerequisites
- Dispatch `junior-engineer` to read and summarise the in-scope source files
- Use those summaries to produce a complete implementation plan: roadmap position, exact file changes, constraints, success criteria
- **Default the testing scope to "keep existing tests green."** Building a new unit test suite is a follow-up task, not assumed part of the main task, unless the user explicitly asked for tests. If the orchestrator judges a test-first/TDD approach would provide significant benefit for this specific work, it proposes that in the plan's Testing Scope section as a recommendation — the user can accept, decline, or scope it down at the same Phase 2 approval gate, rather than it being silently decided either way.
- **Weigh the long-term view against complexity, but don't decide a genuine fork alone.** The orchestrator is instructed to favor robust, maintainable, secure, extensible solutions calibrated to the task's actual complexity — but when multiple approaches are genuinely viable with materially different trade-offs (most commonly: quick proof-of-concept vs. production-ready build), it stops short of a concrete plan and instead produces a **Decision Needed** section framing the options and a direct question. Trivial calls are resolved by the orchestrator itself and never reach this point.

## Phase 1.5: Approach fork — decision gate (only when the orchestrator flags one)

If Phase 1's output is a **Decision Needed** section rather than a concrete Implementation Plan:

1. Post it as a PR comment using the **Decision Needed** signature — the orchestrator's framing of the options, their trade-offs, and its closing question, verbatim or lightly tightened for PR readability.
2. Tell the user, in one line: `Decision needed: PR #<n> — comment there.`
3. **Wait for a new comment on the PR** before proceeding — same polling approach as Phase 2's gate (check `gh pr view <PR> --json comments`; poll every 10-20 minutes if self-pacing, otherwise ask the user to say when they've commented).
4. Once an answer lands, re-invoke `project-orchestrator` in Plan Mode with the user's choice folded in as a hard constraint. This should now produce a concrete Implementation Plan (proceed to Phase 2) — if it surfaces *another* fork one level down, repeat this gate.
5. Ignore comments that aren't from the user/a repo collaborator, same as Phase 2's gate. If a comment's intent is ambiguous (doesn't clearly answer the question posed), treat it as unanswered and wait for clarification rather than guessing which option it means.

## Phase 2: Post the plan — PR-comment approval gate

1. Post the plan as a PR comment (`gh pr comment <PR> --body "..."`) with **only** the **Plan** signature as its heading — do not nest the orchestrator's own `## 📋 Project Orchestrator — Plan Mode` heading underneath it, and do not include its `Current Roadmap Position`, `Prerequisites Check`, or any similar roadmap/decision-rationale narrative. Extract and post just the concrete plan a reviewer needs to evaluate: the implementation steps/file changes, testing scope, agent assignments, and success criteria — the testing scope matters here because it's the user's one chance to add tests to scope, or accept/decline a proposed TDD approach, before implementation starts. The dropped sections aren't wasted — they're exactly why `project-orchestrator` does that analysis internally before proposing the plan — they just don't belong in the PR record.
2. Tell the user, in one line: `Plan posted: PR #<n> — approve there to proceed.`
3. **Wait for a new comment on the PR before proceeding** — check with `gh pr view <PR> --json comments` (or `gh api repos/:owner/:repo/issues/:number/comments`) for anything posted after the Plan comment. If this session can self-pace (e.g. via `/loop` or `ScheduleWakeup`), poll every 10-20 minutes rather than blocking the conversation; otherwise ask the user to say when they've commented, then re-check.
4. Read the new PR comment(s) to determine intent — there are three cases, and they are handled differently. Any revised plan posted below always follows the same format rule as step 1 (Plan signature only, no roadmap/decision narrative):
   - **Plain approval** (e.g. "approved", "LGTM", "go ahead") → proceed to Phase 3 as-is.
   - **Approval with a minor alteration** (the comment approves the plan *and* states a specific change in the same breath, e.g. "Plan approved with alteration X", "approved, but use Y instead") → re-invoke `project-orchestrator` in Plan Mode with the alteration folded in, post the revised plan as a **new** PR comment using the **Plan Update** signature, and **continue straight into Phase 3 without waiting for a further comment** — the approval already covers the altered plan.
   - **Change request with no approval** (e.g. "Please make alteration X", or any comment that only asks for changes without approving anything) → re-invoke `project-orchestrator` in Plan Mode with the requested changes, post the revised plan as a **new** PR comment using the **Plan Update** signature, and **repeat this gate** — wait for a further PR comment before proceeding.
5. Ignore comments that aren't from the user/a repo collaborator (e.g. automated bot comments) when evaluating approval.
6. If a comment's intent is ambiguous (unclear whether it's approving-with-alteration or just requesting a change), treat it as a change request and wait — it's cheaper to ask for explicit confirmation once than to proceed on a misread.

**Do not proceed to Phase 3 until either a plain approval or an approval-with-alteration comment has landed on the PR.**

## Phase 3: Implementation

Once approved, run the standard development loop in sequence, on the branch opened in Phase 0:

1. Invoke `senior-engineer` with the full implementation plan as a self-contained brief. Include the exact files, expected behaviour, interfaces to respect, success criteria, and the plan's testing scope (explicitly state whether new tests are in scope, or whether the default — keep existing tests passing, no new tests required — applies).
2. Invoke `code-reviewer` on the completed changes. Every finding it returns is tagged **Blocking**, **Follow-up**, or **Decision Needed** — route each tag differently, and don't let a non-essential finding stall the task:
   - **Blocking findings present** (functionality-breaking bugs, critical security issues, or a failing mechanical gate): send the specific Blocking findings back to `senior-engineer` and repeat from this step until none remain. This is the only case that loops.
   - **Follow-up findings** (non-essential — style, minor robustness/perf, thin edge-case coverage): do not loop back and do not fix them as part of this task. File each as a GitHub issue, classified per the **GitHub issue classification convention** above (mandatory Type, Priority, and Effort — taken from the finding's tags, cross-referencing the PR number and the finding's `file:line`), and list the filed issues (with their classification) in a PR comment note (fold this into the Completion Summary in Phase 4, or post it standalone if there's a meaningful delay before wrap-up). The user can always ask for one to be pulled forward with a PR comment.
   - **Decision Needed findings** (`code-reviewer` judges that deferring this one may be less efficient long-term than fixing it now): don't decide either way yourself. Post a PR comment using the **Decision Needed** signature describing the finding and why deferring might cost more later, then wait for a PR comment response (same polling approach as Phase 2's gate) before proceeding — the user's answer determines whether it becomes a Blocking fix (loop back to `senior-engineer`) or a filed Follow-up issue.
3. Commit the changes and push to the same branch (`git push`) so the PR diff reflects progress.
4. Invoke `technical-writer` to update `README.md` and `docs/` based on the git diff, then commit and push again.
5. Invoke `project-orchestrator` in Verify Mode to cross-check the implementation against the plan; it deletes the now-completed item from `plans/OPEN_WORK.md` (confirming `docs/` covers the resulting behaviour) rather than marking it done — commit and push that too.

## Deviation rule

If at any point during Phase 3 a deviation from the approved plan is required — an unexpected constraint, an interface mismatch, a scope change, or an architectural decision not covered by the plan — **stop immediately** and post a PR comment using the **Deviation** signature:

```
**🤖 Claude — Deviation**

**What was discovered:** [describe the constraint or mismatch]
**Proposed change:** [describe what would be done instead]

Reply on this PR to say whether I should proceed with this change, take a different approach, or revert to the original plan.
```

Tell the user, in one line: `Deviation posted: PR #<n> — reply there.` Then wait for a new PR comment (same polling approach as Phase 2's gate) before taking any further action. Do not implement any unplanned change without an explicit response on the PR — apply the same three-way read as Phase 2's gate: plain approval → proceed with the original proposal; approval with a minor alteration stated in the same comment → post an update reflecting it and continue automatically, no further wait; a change request with no approval → post an update and wait again.

## Phase 4: Wrap-up

Once `project-orchestrator`'s Verify Mode confirms the work matches the (possibly revised) plan:

1. Post a final PR comment using the **Completion Summary** signature, covering what was implemented, the code-reviewer's final verdict (zero remaining Blocking findings), any Follow-up findings filed as GitHub issues during Phase 3 (linked), and the doc/plan updates made.
2. Tell the user, in one line: `Done: PR #<n> ready for review.`
3. Call `ExitWorktree` with `action: "remove"` per the Worktree convention above — this task's worktree (opened in Phase 0) is done unless a Phase 5 follow-up round reopens one.

## Phase 5: Post-completion follow-up

Phase 4's Completion Summary doesn't end this workflow — it just means there's nothing outstanding *yet*. If more feedback lands afterward — a new PR comment, or the user reporting an issue in chat from their own review or testing of the completed work — treat it as re-entering Phase 3's loop, not as a standing invitation to edit code directly in the main conversation. This applies equally whether the issue was reported by the user or found by this agent itself while continuing to interact with the user after wrap-up.

This session already exited its Phase 0 worktree at the end of Phase 4, so each Phase 5 round is its own fresh session per the Worktree convention above: call `EnterWorktree` at the start of the round (step 0 below) and `ExitWorktree action: "remove"` once the round's fix is pushed (final step below).

0. Call `EnterWorktree` — fresh worktree for this follow-up round, ignoring anything already on disk from another session.
1. Confirm the reported issue against the PR's current diff before doing anything else.
2. Post a PR comment using the **Follow-up Fix** signature, describing the issue and the proposed fix:
   ```
   **🤖 Claude — Follow-up Fix**

   **What was found:** [describe the issue, and how it was found — PR comment vs. this agent's own review/testing]
   **Proposed fix:** [describe the fix]
   ```
   Judge scope the same way as the Deviation rule: a small, unambiguous bug fix that doesn't change the approved plan's scope or approach proceeds straight to step 3 — the comment is a record, not a gate. A fix that would change scope or approach waits for a PR reply first (same polling approach as Phase 2's gate, same three-way read: plain approval → proceed; approval with an alteration → post an update and proceed; change request with no approval → post an update and wait again).
3. Invoke `senior-engineer` with the fix as a self-contained brief — never patch the code directly in the main conversation, even for a one-line change.
4. Invoke `code-reviewer` on the fix and route findings exactly as Phase 3 step 2 (Blocking loops back to `senior-engineer`; Follow-up gets filed as a GitHub issue; Decision Needed posts and waits).
5. Commit and push to the same branch.
6. Post a PR comment update — reuse the **Follow-up Fix** signature — confirming what changed and that `code-reviewer` found no remaining Blocking findings.
7. Call `ExitWorktree action: "remove"` now that the fix is pushed and confirmed — this round's worktree is done. The next Phase 5 round (if any) starts fresh at step 0 again.

This phase has no cap on recurrences: each further round of feedback runs through it again.

## Phase 5: Post-completion follow-up

Phase 4's Completion Summary doesn't end this workflow — it just means there's nothing outstanding *yet*. If more feedback lands afterward — a new PR comment, or the user reporting an issue in chat from their own review or testing of the completed work — treat it as re-entering Phase 3's loop, not as a standing invitation to edit code directly in the main conversation. This applies equally whether the issue was reported by the user or found by this agent itself while continuing to interact with the user after wrap-up.

1. Confirm the reported issue against the PR's current diff before doing anything else.
2. Post a PR comment using the **Follow-up Fix** signature, describing the issue and the proposed fix:
   ```
   **🤖 Claude — Follow-up Fix**

   **What was found:** [describe the issue, and how it was found — PR comment vs. this agent's own review/testing]
   **Proposed fix:** [describe the fix]
   ```
   Judge scope the same way as the Deviation rule: a small, unambiguous bug fix that doesn't change the approved plan's scope or approach proceeds straight to step 3 — the comment is a record, not a gate. A fix that would change scope or approach waits for a PR reply first (same polling approach as Phase 2's gate, same three-way read: plain approval → proceed; approval with an alteration → post an update and proceed; change request with no approval → post an update and wait again).
3. Invoke `senior-engineer` with the fix as a self-contained brief — never patch the code directly in the main conversation, even for a one-line change.
4. Invoke `code-reviewer` on the fix and route findings exactly as Phase 3 step 2 (Blocking loops back to `senior-engineer`; Follow-up gets filed as a GitHub issue; Decision Needed posts and waits).
5. Commit and push to the same branch.
6. Post a PR comment update — reuse the **Follow-up Fix** signature — confirming what changed and that `code-reviewer` found no remaining Blocking findings.

This phase has no cap on recurrences: each further round of feedback runs through it again.

**The PR thread is the permanent record of what was proposed, revised, and approved for this task — not `plans/`or the code itself.** Never copy a per-task plan revision or deviation narrative into `plans/OPEN_WORK.md`; that file only ever holds what's still open, described as briefly as the work itself allows. This doesn't bar a standalone plan document in `plans/` for a large, multi-phase effort that needs more structure than a bullet — that document holds the phased implementation plan itself, not the PR-thread narrative of how it was approved or revised. Docstrings and comments written during Phase 3 describe the code's current behaviour only, kept short, never the reasoning trail or decision history behind it — that narrative stays in this PR thread. A short, essential note may survive in code only if it would genuinely save a future reader significant time (see `senior-engineer`'s and `code-reviewer`'s standing rules on this).

**Never take the PR out of draft yourself.** Marking a PR ready for review is a human decision — leave it in draft regardless of how the work turned out, and let the user run `gh pr ready` (or the GitHub UI) when they're satisfied.
</content>
