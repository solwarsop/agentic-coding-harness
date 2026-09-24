---
name: custom-agent-plan
description: "Full planning and implementation workflow: a branch + draft PR opened at the start of every task, orchestrator-led planning with Haiku-based codebase summarization, a PR-comment decision gate when the plan hinges on a genuine approach trade-off (e.g. proof-of-concept vs. production-ready), a PR-comment approval gate before execution (including the plan's testing scope, since new unit tests default to a follow-up task rather than assumed scope), a single progress checklist comment edited in place (not reposted) as each implementation step completes, PR-comment deviation confirmation during implementation, severity-tiered code review (Blocking/Fix-in-PR/Follow-up/Decision Needed) where only Blocking findings pause the loop, a Fix-in-PR allowance of 25 findings per PR for issues cheaper to fix now than defer, review capped at 4 passes per round (1 exhaustive pass plus up to 3 re-review passes scoped to the revision diff), remaining findings filed as grouped GitHub issues always classified with a mandatory Type (Bug/Task), Priority, and Effort estimate, a PR description rewritten into a concise summary of the change at wrap-up, and a post-completion follow-up phase that routes any issue found after wrap-up (PR comment or the agent's own later testing) back through the same senior-engineer/code-reviewer loop instead of being patched inline."
---

Run the planning and implementation workflow for the user's task. Follow these phases in order and do not skip the approval gate. The guiding principle: **this repo's PR history is the permanent record of what Claude proposed and what the user approved** — every plan, revision, and deviation gets posted as a signed PR comment, not just said in chat.

## Signing convention

Every comment, and the PR description itself, must open with an unambiguous signature line so nothing posted by this workflow is ever mistaken for human-authored content — including while the PR is still a draft:

```
**🤖 Claude — <PR Description / Decision Needed / Plan / Plan Update / Progress / Deviation / Completion Summary / Follow-up Fix>**

<content>
```

## Body-file convention

Every `gh pr create`, `gh pr comment`, or `gh issue create` call that carries one of the signed bodies above must pass it via `--body-file <path>`, **never** `--body "$(...)"`. A worktree-isolated session refuses to run a command whose argument is a runtime-computed value (e.g. `--body "$(printf '...')"`) inside a construct it can't verify is safe, and fails the whole call. Instead:

1. Write the body to a scratch file with a plain `Bash` heredoc: `cat > /tmp/pr_body.md <<'EOF'` ... `EOF` — not the `Write` tool. `enforce-agent-boundaries.sh` restricts what this coordinating session may `Edit`/`Write` inside the repo itself (docs/plans only, per the Worktree convention below), so a `Write` call for a same-purpose scratch file gets denied too; a plain `Bash` heredoc isn't subject to that rule, and a path outside the worktree (e.g. under `/tmp`) is exempt from it entirely.
2. Reference that file's static path with `--body-file`, e.g. `gh pr create --draft --base <base> --title "..." --body-file /tmp/pr_body.md`.

## Worktree convention

This coordinating session works in a single disposable worktree for the whole task, rather than directly in the shared working directory — every subagent it dispatches (`project-orchestrator`, `junior-engineer`, `senior-engineer`, `code-reviewer`, `technical-writer`) inherits that same working directory when invoked, so only this session manages the worktree itself; the subagents don't each need their own.

1. At the start of the task (Phase 0), call `EnterWorktree` with no `name`/`path` (let it generate one) to get a fresh worktree. **Never try to detect, reuse, repair, or clean up an existing or conflicting worktree left by another session** — ignore whatever else is already on disk under `.claude/worktrees/` and let `EnterWorktree` create its own alongside it.
2. Create and push the task's branch inside that worktree (Phase 0 below) — every later phase, and every subagent dispatched from this session, works on that same branch in that same worktree for as long as the task stays open.
3. Once Phase 4's Completion Summary is posted, call `ExitWorktree` with `action: "remove"` (never `"keep"`) so nothing is left behind. If a Phase 5 follow-up round arrives later — possibly much later — treat it as its own fresh session: call `EnterWorktree` again at the start of that round, do the work, and `ExitWorktree action: "remove"` again once it's pushed.

## GitHub issue classification convention

Every GitHub issue filed by this workflow (Phase 3 step 2's Follow-up findings, Late findings, Fix-in-PR items demoted for exceeding the allowance, surviving past pass 4, or skipped by `senior-engineer` as much costlier than briefed, deferred Decision Needed findings — including a deferred post-pass-4 Blocking finding — and Phase 5 step 4's equivalents) must carry all three classifications below — **never file one unclassified.** `code-reviewer` already attaches a Type/Priority/Effort tag to every Fix-in-PR, Follow-up, and Decision Needed finding it reports; use those tags verbatim rather than re-deriving them.

**File grouped issues, not one issue per finding**: one issue per file, or per theme when several findings across files share one cause. Title it `Follow-ups from PR #N: <file|theme>`. Body is a checklist, one line per item: `file:line — description (Type/Priority/Effort)`. Labels for the group: **Type** is `Bug` if any item is a Bug, else `Task`; **Priority** is the highest Priority among its items; **Effort** sums each item's points (S=1, M=3, L=6) and buckets the total — ≤2 is Small, ≤6 is Medium, otherwise Large. Before filing, check for an existing open grouped issue for the same PR and group (e.g. filed in an earlier Phase 5 round): `gh issue list --state open --search "in:title \"Follow-ups from PR #N: <file|theme>\""` — pick the result whose title matches exactly. If one exists, append the new items to its body (`gh issue edit --body-file`) and recompute its labels instead of filing a new issue — the body-file edit alone does not update labels, so also run `gh issue edit <n> --add-label ... --remove-label ...` for any label the recomputed mix changed. Where native Issue Types are in use, also update the type if it changed (`gh issue edit <n> --type Bug` if the installed `gh` supports `--type` on `issue edit`; otherwise update it via the UI or the GraphQL API).

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

## Progress comment convention

Once a plan is approved, Phase 3 tracks its execution with **one** PR comment that gets edited in place as steps complete — never a new comment per step. Keep the checklist coarse: one box per Phase 3 step below (five boxes total), not per file changed or per sub-action within a step. A finer-grained checklist would mean an edit — and the tokens to decide what changed — after nearly every tool call, for no benefit to the reader.

1. At the start of Phase 3, post the checklist with all boxes unchecked using the **Progress** signature and `gh pr comment <PR> --body-file <path>`. `gh pr comment` prints the new comment's URL on success; the trailing number in that URL is the comment ID — keep it for the edits below.
2. As each Phase 3 step below completes, rewrite the body file with that step's box checked (`- [x]`) and push the update with `gh api --method PATCH repos/{owner}/{repo}/issues/comments/<id> -F body=@<path>` (substitute the real owner/repo and the ID captured in step 1) — the same comment, edited, not a new one.
3. While revision/re-review passes are running (at most 4 review passes per review round), leave the checklist as it is until the loop resolves — don't uncheck or re-post over a pass in progress.
4. A Deviation or Decision Needed detour during Phase 3 still gets its own distinct comment per its own convention — the Progress comment only ever tracks the fixed five-step list, it doesn't absorb narrative content.

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
6. Open a **draft** PR whose body opens with the **PR Description** signature (see Signing convention and Body-file convention above): write the body to a scratch file (`cat > /tmp/pr_body.md <<'EOF'` with the **PR Description** signature followed by a one-line description of what this PR will contain, noting that the plan, approvals, and any deviations will follow as comments below, then `EOF`), then `gh pr create --draft --base <base branch> --title "<task summary>" --body-file /tmp/pr_body.md`.
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
3. **Wait for a new comment on the PR before proceeding** — check with `gh pr view <PR> --json comments` (or `gh api repos/:owner/:repo/issues/:number/comments`) for anything posted after the Plan comment. `ScheduleWakeup` is a `/loop` dynamic-mode primitive: it only works when this whole task was itself invoked via `/loop` (which supplies the `prompt` to re-fire on wake) — in that case, poll every 10-20 minutes via `/loop`'s own self-pacing rather than blocking the conversation. **Never call `ScheduleWakeup` directly outside of an active `/loop`** — called on its own it has no `/loop` prompt to resume, and fails with `Error: `prompt` is required when `stop` is not true.` Outside of `/loop`, ask the user to say when they've commented, then re-check.
4. Read the new PR comment(s) to determine intent — there are three cases, and they are handled differently. Any revised plan posted below always follows the same format rule as step 1 (Plan signature only, no roadmap/decision narrative):
   - **Plain approval** (e.g. "approved", "LGTM", "go ahead") → proceed to Phase 3 as-is.
   - **Approval with a minor alteration** (the comment approves the plan *and* states a specific change in the same breath, e.g. "Plan approved with alteration X", "approved, but use Y instead") → re-invoke `project-orchestrator` in Plan Mode with the alteration folded in, post the revised plan as a **new** PR comment using the **Plan Update** signature, and **continue straight into Phase 3 without waiting for a further comment** — the approval already covers the altered plan.
   - **Change request with no approval** (e.g. "Please make alteration X", or any comment that only asks for changes without approving anything) → re-invoke `project-orchestrator` in Plan Mode with the requested changes, post the revised plan as a **new** PR comment using the **Plan Update** signature, and **repeat this gate** — wait for a further PR comment before proceeding.
5. Ignore comments that aren't from the user/a repo collaborator (e.g. automated bot comments) when evaluating approval.
6. If a comment's intent is ambiguous (unclear whether it's approving-with-alteration or just requesting a change), treat it as a change request and wait — it's cheaper to ask for explicit confirmation once than to proceed on a misread.

**Do not proceed to Phase 3 until either a plain approval or an approval-with-alteration comment has landed on the PR.**

## Phase 3: Implementation

Once approved, post the Progress checklist per the **Progress comment convention** above with one unchecked box per step below (Implement, Review, Push, Document, Verify), then run the standard development loop in sequence, on the branch opened in Phase 0:

1. **Implement** — Invoke `senior-engineer` with the full implementation plan as a self-contained brief. Include the exact files, expected behaviour, interfaces to respect, success criteria, and the plan's testing scope (explicitly state whether new tests are in scope, or whether the default — keep existing tests passing, no new tests required — applies). Once it completes, check the Implement box.
2. **Review** — Invoke `code-reviewer` on the completed changes, providing the diff (`git diff` against the base branch) rather than full file contents — `code-reviewer` defaults to reviewing the diff and expands to full-file reads itself only where it judges the diff alone insufficient for context. Every finding it returns is tagged **Blocking**, **Fix-in-PR**, **Follow-up**, or **Decision Needed**. Review is capped at **4 passes per review round**: pass 1 plus up to 3 re-review passes. Only Blocking findings make the verdict NEEDS_REVISION; Blocking findings and Fix-in-PR items both go into the one batched revision, which runs whenever either is present — including on a PASS. The Fix-in-PR allowance (25) is per PR, across every review round (this Phase 3 pass and each later Phase 5 round); the 4-pass cap is per round.
   - **Pass 1**: tell `code-reviewer` this is pass 1 and the full Fix-in-PR allowance (25) is available. Pass 1 is the only exhaustive review — anything it doesn't report here won't be fixed in this PR.
   - **Blocking findings** — functionality-breaking bugs, critical/exploitable security issues, a failing mechanical gate, a finding likely to stop the PR achieving its plan/brief's purpose, or one likely to make testing (tests, a verification step, or the user's own testing) fail or mislead. This is the bar `code-reviewer` applies; treat any finding it tags Blocking as mandatory to fix.
   - **Decision Needed findings** (pass-1 Decision Needed findings also include tie-break escalations, where a finding of unclear purpose/testing impact would be Fix-in-PR but a Fix-in-PR exclusion applies or the allowance is exhausted): post a PR comment using the **Decision Needed** signature describing the finding and why deferring might cost more later, then wait for a PR comment response (same polling approach as Phase 2's gate). Resolve every pass-1 Decision Needed question **before** the first revision, so fix-now items are batched into it. The user's answer determines whether it becomes a fix-now item or a filed Follow-up (joining its group). A failed fix of a Decision Needed item the user chose to fix now is re-queued for the next revision like a Blocking finding — never re-asked as a question a second time.
   - Once Blocking findings and any fix-now items are settled, run **one batched revision**: invoke `senior-engineer` once, covering every open Blocking finding, every Fix-in-PR item, and every Decision Needed item the user chose to fix now. Leave the Review box unchecked while a revision is in flight. If `senior-engineer` reports a **Fix-in-PR item skipped as much costlier than briefed**, demote it to Follow-up (still counts toward `Fix-in-PR used`) and pass that skip into the next pass's review brief so `code-reviewer` doesn't re-report it as a failed fix. **This skip route applies only to Fix-in-PR items — `senior-engineer` may never skip a Blocking finding.** If a Blocking finding turns out much costlier than briefed, `senior-engineer` reports it instead; post it as a Decision Needed PR comment and wait for the reply. During passes 1–3, **"Fix now"** joins the current round's next batched revision, not a fresh round; **"Defer"** files it in its grouped issue with `priority: high` and counts as resolved. Only a Blocking finding still open after pass 4 gets the separate fresh-round treatment with its own 4-pass cap (see below).
   - **Re-review passes (2–4)** review only the diff of that revision. They may report only a fix that didn't work (keeps its tag, goes into the next revision, doesn't consume more allowance) or a regression the fix introduced (tagged Blocking or Follow-up by the normal bar). Anything else the pass notices is a **Late finding** — file it automatically as a Follow-up; it never triggers another revision.
   - The loop stops as soon as a pass leaves nothing to fix — if pass 1 finds nothing Blocking and nothing Fix-in-PR, there is no revision at all.
   - **Never run a fifth pass in this round.** After pass 4, any Blocking finding still open becomes a Decision Needed PR comment and the workflow waits for the user's reply instead of looping again. **"Fix now"** starts a fresh review round scoped to just that finding — one `senior-engineer` revision, its own 4-pass cap, remaining Fix-in-PR allowance carried over. **"Defer"** files it in its grouped issue with `priority: high` and counts as resolved for the completion gates below. Any Fix-in-PR item still open at that point is demoted to Follow-up and filed.
   - File every Follow-up finding, every Fix-in-PR item demoted for exceeding the allowance, surviving past pass 4, or skipped by `senior-engineer` as much costlier than briefed, every deferred Decision Needed item (including a deferred post-pass-4 Blocking finding), and every Late finding as **grouped issues** per the **GitHub issue classification convention** above (one issue per file/theme, mandatory Type/Priority/Effort, checklist body, cross-referencing the PR number). List the filed issues (with their classification) in a PR comment note (fold this into the Completion Summary in Phase 4, or post it standalone if there's a meaningful delay before wrap-up). The user can always ask for a filed item to be pulled forward with a PR comment.
   - Once the loop ends (nothing left to fix, or a still-open Blocking finding has been converted to a Decision Needed comment and, if answered, resolved), check the Review box. The Review box is only checked once any post-pass-4 Decision Needed reply has been received and acted on — Push and Document wait until then.
3. **Push** — Commit the changes and push to the same branch (`git push`) so the PR diff reflects progress. Check the Push box.
4. **Document** — Invoke `technical-writer` to update `README.md` and `docs/` based on the git diff, then commit and push again. Check the Document box.
5. **Verify** — Invoke `project-orchestrator` in Verify Mode to cross-check the implementation against the plan; it deletes the now-completed item from `plans/OPEN_WORK.md` (confirming `docs/` covers the resulting behaviour) rather than marking it done — commit and push that too. Check the Verify box.

## Deviation rule

If at any point during Phase 3 a deviation from the approved plan is required — an unexpected constraint, an interface mismatch, a scope change, or an architectural decision not covered by the plan — **stop immediately** and post a PR comment using the **Deviation** signature:

```
**🤖 Claude — Deviation**

**What was discovered:** [describe the constraint or mismatch]
**Proposed change:** [describe what would be done instead]

Reply on this PR to say whether I should proceed with this change, take a different approach, or revert to the original plan.
```

A Fix-in-PR item is never a Deviation — its exclusions already rule out anything that would change the PR's approved scope or approach.

Tell the user, in one line: `Deviation posted: PR #<n> — reply there.` Then wait for a new PR comment (same polling approach as Phase 2's gate) before taking any further action. Do not implement any unplanned change without an explicit response on the PR — apply the same three-way read as Phase 2's gate: plain approval → proceed with the original proposal; approval with a minor alteration stated in the same comment → post an update reflecting it and continue automatically, no further wait; a change request with no approval → post an update and wait again.

## Phase 4: Wrap-up

Once `project-orchestrator`'s Verify Mode confirms the work matches the (possibly revised) plan:

1. Rewrite the PR description (`gh pr edit <PR> --body-file <path>`) to replace Phase 0's placeholder with a concise summary of the change and its purpose — still opening with the **PR Description** signature. The description is the first thing a reviewer reads; by wrap-up it should describe what actually shipped, not the one-line placeholder written before planning started.
2. Post a final PR comment using the **Completion Summary** signature, covering what was implemented, the code-reviewer's final verdict (zero open Blocking findings — a post-pass-4 Blocking finding counts as closed once resolved through its Decision Needed reply — and no open Fix-in-PR items), the Fix-in-PR items fixed during Phase 3 and the final `Fix-in-PR used: n/25` count, the number of review passes run, any grouped Follow-up issues filed during Phase 3 (linked, with labels), and the doc/plan updates made.
3. Tell the user, in one line: `Done: PR #<n> ready for review.`
4. Call `ExitWorktree` with `action: "remove"` per the Worktree convention above — this task's worktree (opened in Phase 0) is done unless a Phase 5 follow-up round reopens one.

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
4. Invoke `code-reviewer` on the fix and route findings exactly as Phase 3 step 2: pass 1 with the allowance left (25 minus the latest `Fix-in-PR used` count found in the PR thread; if no `Fix-in-PR used` count is found in the PR thread, treat used as 0 (25 left)), capped at 4 passes for this round, Blocking findings batched into one revision, Fix-in-PR items fixed within that same batch up to the allowance, Follow-up and Late findings filed as grouped issues (appending to an existing open group for this PR where one exists), and Decision Needed posted and resolved before the revision.
5. Commit and push to the same branch.
6. Post a PR comment update — reuse the **Follow-up Fix** signature — confirming what changed, that `code-reviewer` found zero open Blocking findings and no open Fix-in-PR items, and the updated `Fix-in-PR used: n/25` count.
7. Call `ExitWorktree action: "remove"` now that the fix is pushed and confirmed — this round's worktree is done. The next Phase 5 round (if any) starts fresh at step 0 again.

This phase has no cap on recurrences: each further round of feedback runs through it again.

**The PR thread is the permanent record of what was proposed, revised, and approved for this task — not `plans/`or the code itself.** Never copy a per-task plan revision or deviation narrative into `plans/OPEN_WORK.md`; that file only ever holds what's still open, described as briefly as the work itself allows. This doesn't bar a standalone plan document in `plans/` for a large, multi-phase effort that needs more structure than a bullet — that document holds the phased implementation plan itself, not the PR-thread narrative of how it was approved or revised. Docstrings and comments written during Phase 3 describe the code's current behaviour only, kept short, never the reasoning trail or decision history behind it — that narrative stays in this PR thread. A short, essential note may survive in code only if it would genuinely save a future reader significant time (see `senior-engineer`'s and `code-reviewer`'s standing rules on this).

**Never take the PR out of draft yourself.** Marking a PR ready for review is a human decision — leave it in draft regardless of how the work turned out, and let the user run `gh pr ready` (or the GitHub UI) when they're satisfied.
</content>
