---
name: custom-agent-plan
description: "Full planning and implementation workflow: a branch + draft PR opened at the start of every task, orchestrator-led planning with Sonnet-based codebase summarization, a PR-comment decision gate when the plan hinges on a genuine approach trade-off (e.g. proof-of-concept vs. production-ready), a PR-comment approval gate before execution (including the plan's testing scope, since new unit tests default to a follow-up task rather than assumed scope), PR-comment deviation confirmation during implementation, and severity-tiered code review where only functionality-blocking or critical findings pause the loop."
---

Run the planning and implementation workflow for the user's task. Follow these phases in order and do not skip the approval gate. The guiding principle: **this repo's PR history is the permanent record of what Claude proposed and what the user approved** — every plan, revision, and deviation gets posted as a signed PR comment, not just said in chat.

## Signing convention

Every comment, and the PR description itself, must open with an unambiguous signature line so nothing posted by this workflow is ever mistaken for human-authored content — including while the PR is still a draft:

```
**🤖 Claude — <PR Description / Decision Needed / Plan / Plan Update / Deviation / Completion Summary>**

<content>
```

## Phase 0: Start work — branch, push, draft PR

Before any planning happens:

0. Determine the base branch and protected/deploy branch for this task:
   - **Base branch**: default to the repository's actual default branch (check `git remote show origin` or `gh repo view --json defaultBranchRef`), unless the user or `CLAUDE.md` names a different integration branch (e.g. a `staging`/`develop` branch used ahead of a protected `main`/`production` branch). Use whatever base you land on consistently through every step below and for the rest of the workflow.
   - **Deploy-triggering branch**: check `CLAUDE.md` and any CI/CD workflow files (e.g. `.github/workflows/*.yml`) for a branch that triggers a production deploy on push/merge. Agent-originated PRs must never target that branch directly unless the user explicitly asks for it — target the integration/base branch instead.
1. Run `git status` and confirm the working tree is clean relative to that base branch (stash or ask the user about anything unexpected first — never branch off uncommitted work that isn't yours).
2. Create a branch off the base branch, named `<prefix>/<short-kebab-slug-of-the-task>` — **no `claude/` prefix.** Pick the conventional prefix that matches the task, same vocabulary as this repo's commit messages: `fix/` for a bug fix, `feat/` for new functionality, `chore/` for tooling/maintenance, `docs/` for documentation-only work, `test/` for test-only additions, `refactor/` for a behavior-preserving restructure. When an issue number is available, fold it into the slug (e.g. `fix/early-stopping-patience-34`).
3. GitHub won't open a PR from a branch with no commits ahead of base, so create an empty commit to seed it: `git commit --allow-empty -m "<prefix>: start <task summary>"` (same prefix as the branch name).
4. Push with `-u`: `git push -u origin <prefix>/<slug>`.
5. Open a **draft** PR whose body opens with the **PR Description** signature (see Signing convention below): `gh pr create --draft --base <base branch> --title "<task summary>" --body "$(printf '**🤖 Claude — PR Description**\n\n<one-line description of what this PR will contain; note that the plan, approvals, and any deviations will follow as comments below>')"`.
6. Note the PR number/URL and the base branch used — every later phase posts comments to this same PR.

Tell the user the PR is open and that planning is starting.

## Phase 1: Orchestrator planning

Invoke `project-orchestrator` in Plan Mode with the user's task description. The orchestrator will:
- Read `plans/OPEN_WORK.md` — the rolling list of open work and the default home for a new item (standalone plan documents are also allowed in `plans/` for larger, multi-phase efforts, pointed to from `OPEN_WORK.md`) — and confirm this is the correct next step
- Check prerequisites
- Dispatch `software-engineer` to read and summarise the in-scope source files
- Use those summaries to produce a complete implementation plan: roadmap position, exact file changes, constraints, success criteria
- **Default the testing scope to "keep existing tests green."** Building a new unit test suite is a follow-up task, not assumed part of the main task, unless the user explicitly asked for tests. If the orchestrator judges a test-first/TDD approach would provide significant benefit for this specific work, it proposes that in the plan's Testing Scope section as a recommendation — the user can accept, decline, or scope it down at the same Phase 2 approval gate, rather than it being silently decided either way.
- **Weigh the long-term view against complexity, but don't decide a genuine fork alone.** The orchestrator is instructed to favor robust, maintainable, secure, extensible solutions calibrated to the task's actual complexity — but when multiple approaches are genuinely viable with materially different trade-offs (most commonly: quick proof-of-concept vs. production-ready build), it stops short of a concrete plan and instead produces a **Decision Needed** section framing the options and a direct question. Trivial calls are resolved by the orchestrator itself and never reach this point.

## Phase 1.5: Approach fork — decision gate (only when the orchestrator flags one)

If Phase 1's output is a **Decision Needed** section rather than a concrete Implementation Plan:

1. Post it as a PR comment using the **Decision Needed** signature — the orchestrator's framing of the options, their trade-offs, and its closing question, verbatim or lightly tightened for PR readability.
2. Tell the user in chat that a decision is needed before planning can continue, and point them to the PR.
3. **Wait for a new comment on the PR** before proceeding — same polling approach as Phase 2's gate (check `gh pr view <PR> --json comments`; poll every 10-20 minutes if self-pacing, otherwise ask the user to say when they've commented).
4. Once an answer lands, re-invoke `project-orchestrator` in Plan Mode with the user's choice folded in as a hard constraint. This should now produce a concrete Implementation Plan (proceed to Phase 2) — if it surfaces *another* fork one level down, repeat this gate.
5. Ignore comments that aren't from the user/a repo collaborator, same as Phase 2's gate. If a comment's intent is ambiguous (doesn't clearly answer the question posed), treat it as unanswered and wait for clarification rather than guessing which option it means.

## Phase 2: Post the plan — PR-comment approval gate

1. Post the plan as a PR comment (`gh pr comment <PR> --body "..."`) with **only** the **Plan** signature as its heading — do not nest the orchestrator's own `## 📋 Project Orchestrator — Plan Mode` heading underneath it, and do not include its `Current Roadmap Position`, `Prerequisites Check`, or any similar roadmap/decision-rationale narrative. Extract and post just the concrete plan a reviewer needs to evaluate: the implementation steps/file changes, testing scope, agent assignments, and success criteria — the testing scope matters here because it's the user's one chance to add tests to scope, or accept/decline a proposed TDD approach, before implementation starts. The dropped sections aren't wasted — they're exactly why `project-orchestrator` does that analysis internally before proposing the plan — they just don't belong in the PR record.
2. In chat, tell the user the plan has been posted and point them to the PR: "Posted the implementation plan as a comment on PR #<n> (<url>). Please leave an approval comment on the PR (e.g. 'approved') to proceed, or comment with what to change — that comment is the record we're keeping, so please approve there rather than only here in chat."
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

1. Invoke `software-engineer` with the full implementation plan as a self-contained brief. Include the exact files, expected behaviour, interfaces to respect, success criteria, and the plan's testing scope (explicitly state whether new tests are in scope, or whether the default — keep existing tests passing, no new tests required — applies).
2. Invoke `code-reviewer` on the completed changes. Every finding it returns is tagged **Blocking**, **Follow-up**, or **Decision Needed** — route each tag differently, and don't let a non-essential finding stall the task:
   - **Blocking findings present** (functionality-breaking bugs, critical security issues, or a failing mechanical gate): send the specific Blocking findings back to `software-engineer` and repeat from this step until none remain. This is the only case that loops.
   - **Follow-up findings** (non-essential — style, minor robustness/perf, thin edge-case coverage): do not loop back and do not fix them as part of this task. File each as a GitHub issue (`gh issue create --title "..." --body "..."`, cross-referencing the PR number and the finding's `file:line`), and list the filed issues in a PR comment note (fold this into the Completion Summary in Phase 4, or post it standalone if there's a meaningful delay before wrap-up). The user can always ask for one to be pulled forward with a PR comment.
   - **Decision Needed findings** (`code-reviewer` judges that deferring this one may be less efficient long-term than fixing it now): don't decide either way yourself. Post a PR comment using the **Decision Needed** signature describing the finding and why deferring might cost more later, then wait for a PR comment response (same polling approach as Phase 2's gate) before proceeding — the user's answer determines whether it becomes a Blocking fix (loop back to `software-engineer`) or a filed Follow-up issue.
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

Tell the user in chat that a deviation comment is waiting on the PR, then wait for a new PR comment (same polling approach as Phase 2's gate) before taking any further action. Do not implement any unplanned change without an explicit response on the PR — apply the same three-way read as Phase 2's gate: plain approval → proceed with the original proposal; approval with a minor alteration stated in the same comment → post an update reflecting it and continue automatically, no further wait; a change request with no approval → post an update and wait again.

## Phase 4: Wrap-up

Once `project-orchestrator`'s Verify Mode confirms the work matches the (possibly revised) plan:

1. Post a final PR comment using the **Completion Summary** signature, covering what was implemented, the code-reviewer's final verdict (zero remaining Blocking findings), any Follow-up findings filed as GitHub issues during Phase 3 (linked), and the doc/plan updates made.
2. Tell the user in chat that the work is complete and the PR is ready for their review.

**The PR thread is the permanent record of what was proposed, revised, and approved for this task — not `plans/`or the code itself.** Never copy a per-task plan revision or deviation narrative into `plans/OPEN_WORK.md`; that file only ever holds what's still open, described as briefly as the work itself allows. This doesn't bar a standalone plan document in `plans/` for a large, multi-phase effort that needs more structure than a bullet — that document holds the phased implementation plan itself, not the PR-thread narrative of how it was approved or revised. Docstrings and comments written during Phase 3 describe the code's current behaviour only, kept short, never the reasoning trail or decision history behind it — that narrative stays in this PR thread. A short, essential note may survive in code only if it would genuinely save a future reader significant time (see `software-engineer`'s and `code-reviewer`'s standing rules on this).

**Never take the PR out of draft yourself.** Marking a PR ready for review is a human decision — leave it in draft regardless of how the work turned out, and let the user run `gh pr ready` (or the GitHub UI) when they're satisfied.
</content>
