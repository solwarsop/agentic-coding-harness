---
name: custom-agent-plan
description: "Planning and implementation workflow: branch + draft PR, orchestrator planning, PR-comment approval gate, progress checklist, severity-tiered code review with a 4-pass cap, grouped classified GitHub issues, and post-completion follow-up. Every plan, deviation and decision is a signed PR comment."
---

Run the planning and implementation workflow for the user's task. Follow the phases in order and do not skip the approval gate. **This repo's PR thread is the permanent record of what Claude proposed and what the user approved** — every plan, revision and deviation is a signed PR comment, not just said in chat, and never copied into `plans/OPEN_WORK.md` (which holds only what's still open; a standalone `plans/` document for a large multi-phase effort holds the phased plan, not the approval narrative). Docstrings and comments written in Phase 3 describe current behaviour only; decision history stays in the PR thread.

## Signing convention

Every comment, and the PR description, opens with a signature line so nothing posted here is mistaken for human-authored content:

```
**🤖 Claude — <PR Description / Decision Needed / Plan / Plan Update / Progress / Deviation / Completion Summary / Follow-up Fix>**

<content>
```

## Reference convention

GitHub auto-links `#n` in comments, descriptions, issue bodies and commit messages. Use `#n` only for a real issue or PR in this repo that you mean to link. Refer to everything else without the hash ("follow-up 1", "finding 2", "step 3", "Fix-in-PR item 2"); backticks don't stop auto-linking in every context. Off-GitHub numbering: plain `No. 1` or `item 1`.

## Body-file convention

Every `gh pr create`, `gh pr comment`, `gh pr edit` or `gh issue create` call carrying a signed body passes it via `--body-file <path>`, **never** `--body "$(...)"`. Write the body with a Bash heredoc to `/tmp` (`cat > /tmp/pr_body.md <<'EOF'` ... `EOF`), then reference that static path, e.g. `gh pr create --draft --base <base> --title "..." --body-file /tmp/pr_body.md`.

## Worktree convention

This coordinating session works in one disposable worktree; every dispatched subagent inherits its working directory, so only this session manages it.

- **Lifecycle.** Call `EnterWorktree` (no `name`/`path`) at the start of the task, of each Phase 5 round, and on resuming after any pause (then check out the task's branch from `origin`). Call `ExitWorktree` with `action: "remove"` (never `"keep"`) at every pause where the turn ends and at the end of the task or round.
- **Never detect, reuse, repair or clean up** a worktree left by another session; ignore `.claude/worktrees/` contents and let `EnterWorktree` create its own.
- **Never force removal** (never `discard_changes: true`). If `ExitWorktree` refuses because of uncommitted or unpushed work, commit and push to the task's branch and retry; if it still refuses, leave the worktree and report why in the PR comment.
- **Auto memory is disabled** (`autoMemoryEnabled: false` in `settings.json`), so no `.claude/agent-memory/` should appear. If a stray one blocks removal, run `rm -r .claude/agent-memory` from the worktree root and retry; it is gitignored scratch. Record anything worth keeping in `CLAUDE.md`, `plans/` or `docs/`.

## Wait gate

Whenever the workflow needs a user reply or its turn is ending (Decision Needed, the Phase 2 plan, a Deviation, a scope-changing Follow-up Fix, any other pause), run this gate:

1. Commit all work so far (even if incomplete) and push it (`git push`) *before* posting; a session can be reclaimed and unpushed commits are lost. With nothing new to commit, confirm with `git status` and `git log @{u}..` that the branch is fully pushed.
2. Post the pending comment (call sites say which) and give the user its one-line notice.
3. Call `ExitWorktree` with `action: "remove"` and **end the turn**. Never poll PRs, loop, or call `ScheduleWakeup`; the reply arrives as a new message or session.
4. On resume, `EnterWorktree`, then read `gh pr view <PR> --json comments` for comments after yours. Ignore comments not from the user or a repo collaborator (e.g. bots).
5. For a **Decision Needed** comment the reply is the chosen option (or fix now / defer) and the phase continues; an ambiguous reply → wait for clarification. For a Plan, Plan Update, Deviation or scope-changing Follow-up Fix, read intent three ways. **Plain approval** ("approved", "LGTM", "go ahead") → proceed. **Approval plus an alteration** in the same comment ("approved, but use Y") → post an update reflecting it (a **Plan Update** for a plan, re-invoking `project-orchestrator` in Plan Mode with the change first; for a Deviation, an update comment) and continue without waiting again. **Change request without approval** → the same update, then run this gate again. A comment that is ambiguous or doesn't clearly answer is treated as unanswered / a change request: wait for clarification rather than guess.

## GitHub issue classification convention

Every GitHub issue filed by this workflow (Phase 3 step 2's Follow-up findings, Late findings, demoted/surviving/skipped Fix-in-PR items, deferred Decision Needed findings, and Phase 5's equivalents) carries all three classifications below — **never file one unclassified.** `code-reviewer` tags every Fix-in-PR, Follow-up and Decision Needed finding with Type/Priority/Effort; use those tags verbatim.

**File grouped issues, not one per finding**: one issue per file, or per theme when findings across files share a cause. Title `Follow-ups from PR #N: <file|theme>`; body is a checklist, one line per item: `file:line — description (Type/Priority/Effort)`. Group classification: **Type** is `Bug` if any item is a Bug, else `Task`; **Priority** is the highest among items; **Effort** sums points (S=1, M=3, L=6) and buckets the total — ≤2 is Small, ≤6 is Medium, otherwise Large. Before filing, look for an existing open group for the same PR (e.g. from an earlier Phase 5 round): `gh issue list --state open --search "in:title \"Follow-ups from PR #N: <file|theme>\""` — pick the result whose title matches exactly. If one exists, append the new items to its body (`gh issue edit --body-file`) and recompute its classification; the body edit alone doesn't update type/labels/native fields, so also do whichever changed:
  - **Labels** (Priority/Effort when using the label fallback, and Type when native types aren't enabled): `gh issue edit <n> --add-label ... --remove-label ...`.
  - **Native Type**, when in use: `gh issue edit <n> --type Bug` if `gh` supports it; otherwise via the UI (raw `gh api graphql` isn't auto-allowed).
  - **Native Priority/Effort fields**, when in use: re-set whichever value changed (same write call as at filing; read current values with `../../scripts/issue-meta.sh fields-get <owner>/<repo> <n>`).

- **Type** — prefer native GitHub Issue Types. Check once per task:
  ```
  ../../scripts/issue-meta.sh issue-types <owner>/<repo>
  ```
  A non-empty `issueTypes` list means pass `--type Bug` or `--type Task` to `gh issue create`. **Only a query that succeeds and returns an empty/null list** means fall back to a `type: bug` / `type: task` label, created first if missing (see label table).
- **Fail closed, never fall back on an error.** Labels are a fallback for "the feature isn't enabled", not for "the check or command didn't work". If any of these fails — the `issue-types` query (blocked, denied, token scope, malformed response), the `fields-get` check (any exit other than 0 or 4), a `--type` flag on `gh issue create`/`gh issue edit` (e.g. `gh` too old, or the type name doesn't match), or a call setting a native Priority/Effort value — **stop and report the failing command and its error** (in the PR/issue comment) rather than retrying without the flag or adding a `type:`/`priority:`/`effort:` label. Never create an issue unclassified or with labels in place of a native field that exists. The user can then fix permissions (`settings.json` must allow `gh issue edit*` and `issue-meta.sh`) and re-run.
- **Priority** and **Effort** — prefer native **issue fields** (single-select fields `Priority` and `Effort` in the issue sidebar; they live on the issue, not in a Project). Check once per task against the issue just created (or any existing issue):
  ```
  ../../scripts/issue-meta.sh fields-get <owner>/<repo> <number>
  ```
  - **Exit 0** (HTTP 200; a JSON list, possibly empty) means fields are enabled — set `Priority` and `Effort` natively by option ID (an issue with values lists the IDs in use). **The native Effort field uses a `High`/`Medium`/`Low` scale, unlike the finding's `Small`/`Medium`/`Large` — map `Small → Low`, `Medium → Medium`, `Large → High`.** Priority maps directly.
  - **Exit 4** (HTTP 404, repo without issue fields) means not enabled — use labels.
  - **Any other non-zero exit** (denied, token scope, 5xx, malformed response), or a failed attempt to *set* a value on a repo that returned 200, is an error — fail closed.

  Set values with `../../scripts/issue-meta.sh fields-set <owner>/<repo> <number> <fields.json>`, writing the JSON under `/tmp` (the script rejects files not under `/tmp` or `$TMPDIR`, or over 64 KiB). From the project root use `.claude/scripts/issue-meta.sh`. The payload shape is unverified; if the call errors, stop and report the exact command and error rather than guessing a variant.

**Label fallback** (Type only when native types are unavailable; Priority/Effort only after exit 4). Create idempotently before use: `gh label create "<name>" --color <hex> --force`.

Label (colour):
- Type: `type: bug` (d73a4a), `type: task` (1d76db)
- Priority: `priority: high` (b60205), `priority: medium` (fbca04), `priority: low` (0e8a16)
- Effort: `effort: small` (c2e0c6), `effort: medium` (fef2c0), `effort: large` (f9d0c4)

Example, native Issue Types and native fields enabled (Effort `Small` mapped to `Low`):
```
gh issue create --title "..." --body-file /tmp/issue_body.md --type Bug
../../scripts/issue-meta.sh fields-get <owner>/<repo> <number>   # exit 0 -> set Priority=High, Effort=Low by option ID
```
With native types but no fields (check returned 404), add `--label "priority: high" --label "effort: small"`; with neither, use `--label "type: bug"` instead of `--type Bug`.

## Progress comment convention

Once a plan is approved, Phase 3 tracks execution with **one** PR comment edited in place, never a new comment per step. Top level is coarse: five boxes (Implement, Review, Push, Document, Verify). Implement carries the plan's numbered steps as a sub-checklist ticked by `tick-progress.sh`; Review carries a "Review rounds" table. Run the script as `../../scripts/tick-progress.sh` in the task worktree (the normal case) or `.claude/scripts/tick-progress.sh` from the project root, with that literal path as the first word of the command (no variables, no `cd ... &&`, no `bash` prefix) so the permission allow rules match.

1. At the start of Phase 3, post the body with all boxes unchecked using the **Progress** signature and `gh pr comment <PR> --body-file <path>`. Under Implement, copy the plan's numbered steps, one line each: `  - [ ] 1. <one-line label>`. Under Review, add a table with columns `Pass | Scope | Verdict | Blocking | Fix-in-PR | Follow-up | Fixed`. `gh pr comment` prints the comment's URL; its trailing number is the comment ID — keep it.
2. As each Phase 3 step completes, check its box and push the update with `../../scripts/tick-progress.sh --set-body {owner}/{repo} <id> /tmp/progress_body.md` (real owner/repo and ID; the file must be under `/tmp`, written per the Body-file convention). Engineers tick concurrently, so **re-fetch the body** (`../../scripts/tick-progress.sh --body {owner}/{repo} <id>`), save it to `/tmp/progress_body.md`, and edit that before every rewrite; never edit a stale body.
3. After each review pass, append a Review rounds row (pass, scope, verdict, counts of Blocking / Fix-in-PR / Follow-up findings, how many fixed). Leave the Review box unchecked until the loop resolves. At most 4 passes per round.
4. The coordinator owns the five boxes and the table; `senior-engineer` ticks only its own sub-boxes. Deviation and Decision Needed detours get their own comments; no narrative in the Progress comment.
5. **Deviations extend the same comment.** Once a Deviation (or approved-with-alteration update) is answered and work resumes, re-fetch the body and append the deviation's work to Implement as new numbered steps continuing the sequence, e.g. `  - [ ] 6. Deviation: <one-line label>`, and pass those numbers to `senior-engineer` with the usual tick-script instruction. Strike dropped steps through (`~~...~~`) rather than deleting them. Uncheck any box the deviation invalidates (at minimum Review, Push and Verify if checked) and append a Review rounds row for each new pass.
6. **Every later round gets its own Progress comment.** Each Phase 5 follow-up round, and each fresh review round after pass 4, posts a new comment at round start, signed `**🤖 Claude — Progress (Follow-up round <n>)**`, same mechanics as rules 1-4 but with three boxes: Implement (the fix's steps as sub-items), Review (its own table), Push. Add Document and Verify only if the round touches docs or `plans/`. Keep that comment's ID and never reuse an earlier round's.

## Phase 0: Start work — branch, push, draft PR

0. `EnterWorktree` per the Worktree convention.
1. Determine the base and deploy branches:
   - **Base**: the repository's default branch (`git remote show origin` or `gh repo view --json defaultBranchRef`), unless the user or `CLAUDE.md` names another integration branch (e.g. `staging`/`develop`). Use it throughout.
   - **Deploy-triggering branch**: check `CLAUDE.md` and `.github/workflows/*.yml`. Agent PRs never target it unless the user explicitly asks.
2. Confirm with `git status` the tree is clean relative to base.
3. Create a branch `<prefix>/<short-kebab-slug-of-the-task>` — **no `claude/` prefix.** Prefix by task: `fix/`, `feat/`, `chore/`, `docs/`, `test/`, `refactor/`. Fold an issue number into the slug when available.
4. Seed the PR with an empty commit (a PR needs a commit ahead of base): `git commit --allow-empty -m "<prefix>: start <task summary>"`.
5. Push with `-u`: `git push -u origin <prefix>/<slug>`. `--no-track` is a `git checkout`/`git branch` flag that `git push` rejects; if you branched with `--no-track`, set upstream with `git push -u origin HEAD:<branch>` or `git branch --set-upstream-to`.
6. Open a **draft** PR: body is the **PR Description** signature plus a one-line description, noting the plan, approvals and deviations follow as comments (Body-file convention), then `gh pr create --draft --base <base branch> --title "<task summary>" --body-file /tmp/pr_body.md`.
7. Note the PR number/URL and base branch; every later phase comments on this PR.

Tell the user, in one line: `PR #<n> open — planning starting.`

## Phase 1: Orchestrator planning

Invoke `project-orchestrator` in Plan Mode with the user's task. It returns either a complete implementation plan or a **Decision Needed** section (a genuine approach fork it won't decide alone). Dispatching, the testing-scope default and fork detection are in `project-orchestrator.md`. Web lookups are never done by the root session or the orchestrator; they go through `web-researcher`.

## Phase 1.5: Approach fork — decision gate (only when the orchestrator flags one)

If Phase 1 returned a **Decision Needed** section instead of a plan:

1. Compose a PR comment with the **Decision Needed** signature: the options, trade-offs and closing question, verbatim or lightly tightened.
2. Run the **Wait gate** with it; notice: `Decision needed: PR #<n> — comment there.`
3. Once answered, re-invoke `project-orchestrator` in Plan Mode with the choice as a hard constraint. It should now return a plan (proceed to Phase 2); if it surfaces another fork, repeat this gate.

## Phase 2: Post the plan — PR-comment approval gate

1. Compose the plan as a PR comment (body file for `gh pr comment <PR> --body-file <path>`) with **only** the **Plan** signature as its heading. Drop the orchestrator's `## 📋 Project Orchestrator — Plan Mode` heading, `Current Roadmap Position`, `Prerequisites Check` and any similar roadmap/decision narrative. Keep the implementation steps/file changes, testing scope, agent assignments and success criteria. The testing scope matters: it is the user's one chance to add tests to scope, or accept/decline a proposed TDD approach, before implementation.
2. Run the **Wait gate** with it; notice: `Plan posted: PR #<n> — approve there to proceed.`
3. Approval with a minor alteration and a change request both re-invoke `project-orchestrator` in Plan Mode with the change folded in, then post the result as a Plan Update (step 1's format rule: Plan Update signature only, no roadmap narrative). The alteration case continues into Phase 3 without waiting; a change request runs the Wait gate again.

**Do not proceed to Phase 3 until a plain approval or an approval-with-alteration comment has landed on the PR.**

## Phase 3: Implementation

Once approved, post the Progress checklist (**Progress comment convention**), then run the loop in sequence on the Phase 0 branch:

1. **Implement** — Invoke `senior-engineer` with the full plan as a self-contained brief: exact files, expected behaviour, interfaces to respect, success criteria, and the plan's testing scope (state explicitly whether new tests are in scope or the default applies — keep existing tests passing, no new tests required). Include the Progress comment ID and owner/repo, and instruct it to run `../../scripts/tick-progress.sh <owner/repo> <id> <n>` (literal path) after each plan step, ticking only its own sub-boxes. Check Implement when it completes.
2. **Review** — Invoke `code-reviewer` with the diff (`git diff` against base), not full files. Tags **Blocking**/**Fix-in-PR**/**Follow-up**/**Decision Needed**: meanings, cost test and exclusions are in `.claude/agents/code-reviewer.md`. Capped at **4 passes per round**: pass 1 exhaustive, up to 3 re-review passes. Only Blocking makes the verdict NEEDS_REVISION; Blocking and Fix-in-PR go into one batched revision, run whenever either is present, including on a PASS. Tell `code-reviewer` which pass it is.
   - **Decision Needed findings (pass 1)**: compose a **Decision Needed**-signature comment describing the finding and why deferring might cost more, and run the **Wait gate** with it. Resolve every pass-1 Decision Needed question **before** the first revision so fix-now items are batched into it. The answer yields a fix-now item or a filed Follow-up. A failed fix of a fix-now Decision Needed item is re-queued like a Blocking finding, never re-asked.
   - **One batched revision**: once Blocking findings and fix-now items are settled, invoke `senior-engineer` once covering every open Blocking finding, Fix-in-PR item and fix-now Decision Needed item, with the same Progress ID, owner/repo and tick-script instruction. Leave Review unchecked while it runs.
   - **Skips**: if `senior-engineer` reports a **Fix-in-PR item skipped as much costlier than briefed**, demote it to Follow-up and pass that skip into the next review brief so it isn't re-reported as a failed fix. **Only Fix-in-PR items may be skipped; never a Blocking finding.** A costly Blocking finding is composed as a Decision Needed comment and run through the **Wait gate**: in passes 1–3, "Fix now" joins the current round's next batched revision (not a fresh round) and "Defer" files it in its grouped issue with Priority set to High (native field or label, per the classification convention) and counts as resolved.
   - **Re-review passes (2–4)** review only the revision diff and report only a failed fix (keeps its tag, goes into the next revision) or a regression (Blocking or Follow-up). Anything else is a **Late finding**, filed as a Follow-up, never triggering another revision.
   - After each pass, append its Review rounds row (Progress rule 3).
   - The loop stops as soon as a pass leaves nothing to fix. **Never run a fifth pass in a round.** After pass 4, an open Blocking finding is composed as a Decision Needed comment and run through the **Wait gate** ("Fix now" → a fresh review round scoped to it, one revision, its own 4-pass cap; "Defer" → filed in its grouped issue with Priority High, counts as resolved). An open Fix-in-PR item after pass 4 is demoted to Follow-up.
   - File every Follow-up, demoted/surviving/skipped Fix-in-PR item, deferred Decision Needed item and Late finding as **grouped issues** per the classification convention. List them (with classification) in the Completion Summary, or a standalone PR comment if there's a meaningful delay.
   - Check Review once the loop ends **and** any post-pass-4 Decision Needed reply has been acted on, not while WAITING on one. Push and Document wait until then.
3. **Push** — Commit and `git push` to the same branch. Check Push.
4. **Document** — Invoke `technical-writer` to update `README.md` and `docs/` from the git diff; commit and push. Check Document.
5. **Verify** — Invoke `project-orchestrator` in Verify Mode to cross-check the implementation against the plan; it deletes the completed item from `plans/OPEN_WORK.md` (confirming `docs/` covers the resulting behaviour) rather than marking it done. Commit and push that too. Check Verify.

## Deviation rule

If during Phase 3 a deviation from the approved plan is required (unexpected constraint, interface mismatch, scope change, an architectural decision the plan doesn't cover), **stop immediately** and compose a PR comment with the **Deviation** signature:

```
**🤖 Claude — Deviation**

**What was discovered:** [describe the constraint or mismatch]
**Proposed change:** [describe what would be done instead]

Reply on this PR to say whether I should proceed with this change, take a different approach, or revert to the original plan.
```

A Fix-in-PR item is never a Deviation; its exclusions already rule out anything changing the approved scope or approach.

Run the **Wait gate** with it; notice: `Deviation posted: PR #<n> — reply there.` Implement no unplanned change without an explicit response on the PR. Once resolved, record the deviation in the Progress comment per rule 5 before invoking `senior-engineer`.

## Phase 4: Wrap-up

Once Verify Mode confirms the work matches the (possibly revised) plan:

1. Rewrite the PR description (`gh pr edit <PR> --body-file <path>`) from Phase 0's placeholder into a concise summary of what shipped and why, still opening with the **PR Description** signature.
2. Post a final PR comment with the **Completion Summary** signature: what was implemented, the final review verdict (zero open Blocking findings, no open Fix-in-PR items), Fix-in-PR items fixed during Phase 3, review passes run, grouped Follow-up issues filed (linked, with labels), and doc/plan updates made.
3. Tell the user, in one line: `Done: PR #<n> ready for review.`
4. `ExitWorktree` per the Worktree convention.

## Phase 5: Post-completion follow-up

The Completion Summary doesn't end the workflow. Feedback afterward (a PR comment, a user-reported issue, or one this agent finds) re-enters Phase 3's loop; never edit code directly in the main conversation. Each round is its own session per the Worktree convention.

0. `EnterWorktree`.
1. Confirm the reported issue against the PR's current diff first.
2. Compose a PR comment with the **Follow-up Fix** signature:
   ```
   **🤖 Claude — Follow-up Fix**

   **What was found:** [describe the issue, and how it was found — PR comment vs. this agent's own review/testing]
   **Proposed fix:** [describe the fix]
   ```
   A small, unambiguous fix within the approved scope and approach posts the comment directly and proceeds to step 3 (a record, not a gate); otherwise run the **Wait gate** with it first.
3. Once cleared, post this round's Progress comment (rule 6), then invoke `senior-engineer` with the fix as a self-contained brief (new Progress ID, owner/repo, tick-script instruction); never patch the code directly in the main conversation, even for one line.
4. Invoke `code-reviewer` on the fix and route findings exactly as Phase 3 step 2 (pass 1, 4-pass cap for this round, one batched revision, Follow-up and Late findings filed as grouped issues, appending to an existing open group for this PR where one exists, Decision Needed resolved before the revision).
5. Commit and push to the same branch, appending each pass to this round's Review rounds table and checking Implement, Review and Push as each completes.
6. Post a PR comment update (reuse the **Follow-up Fix** signature) confirming what changed and that `code-reviewer` found zero open Blocking findings and no open Fix-in-PR items.
7. `ExitWorktree` per the Worktree convention.

This phase has no cap on recurrences.

**Never take the PR out of draft yourself.** Marking a PR ready for review is a human decision: leave it in draft however the work turned out, and let the user run `gh pr ready` (or the GitHub UI).
