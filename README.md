# Sol's Agentic Coding Harness

Project-agnostic Claude Code configuration—custom agents, skills, and
settings—meant to be reused across multiple projects rather than
copy-pasted into each one.

This repo is designed to be added as a **git submodule at `.claude`** in a
host repository, so Claude Code picks it up automatically as that project's
configuration.

## Layout

- `agents/` — custom subagent definitions
- `skills/` — custom skills
- `hooks/` — hook scripts wired up in `settings.json`
- `scripts/` — helper scripts, mostly invoked by skills (e.g. `tick-progress.sh` ticks
  plan sub-steps in `custom-agent-plan`'s Progress PR comment; `issue-meta.sh`
  reads and writes issue types and native issue fields for `custom-agent-plan`'s
  issue classification; `lib-gh-helpers.sh` is the shared helper library both
  scripts source, not run directly; `check-prompt-invariants.sh` is a maintainer
  check that the load-bearing literals in the agent and skill prompts are still
  present, to run after editing any prompt file; `prompt-ab-test.sh` is a
  maintainer A/B regression test that runs each agent and the
  `custom-agent-plan` skill with prompts from two git refs on a fixture project
  and reports per-check regressions)
- `tests/prompt-ab/` — fixture project, per-case definitions, the offline `gh`
  stub, and saved results for `scripts/prompt-ab-test.sh`
- `settings.json` — shared Claude Code settings

## Agent role boundaries

The file-scope rules stated in each `agents/*.md` (e.g. `project-orchestrator`
never reads or writes source directly, `technical-writer` only touches docs,
`senior-engineer` never touches docs/plans, `junior-engineer` never writes
anything at all) are enforced technically, not just by prompt text:
`settings.json` wires a `PreToolUse` hook to
`hooks/enforce-agent-boundaries.sh`, which reads each tool call's
`agent_type`/`agent_id` and denies calls outside an agent's declared scope.
Scope is matched on path shape rather than on top-level directories alone, so
nested documentation is classified like its top-level counterpart: `docs/` and
`plans/` match at any depth, and a `README.md`/`CLAUDE.md` in a subdirectory
(e.g. `pipelines/README.md`) counts as documentation/plan just as the root one
does. `project-orchestrator` may read any Markdown file — Markdown is
documentation, not source — plus non-Markdown assets under `docs/` or `plans/`;
everything else still has to come back as a `junior-engineer` summary.

`web-researcher` is the one agent with no repo access at all: the hook denies
it `Edit`, `Write`, `NotebookEdit`, `Read`, and `Bash`, leaving only its web
tools (`WebFetch`, `WebSearch`). `project-orchestrator` has no web tools, so
external facts it needs are dispatched to `web-researcher`. `senior-engineer`
keeps `WebFetch`/`WebSearch` for quick documentation lookups only; larger
research goes to `web-researcher`. Web tool access is set by each agent's
`tools` list, not by the hook.

The same hook also denies a root/coordinating session from editing source
directly while it's working inside a `.claude/worktrees/` checkout (i.e.
mid-flight on a worktree-owning skill like `custom-agent-plan`) — a root
session working in the normal repo path is unaffected. This restriction only
applies to paths inside the repo/worktree itself: a scratch file written
outside it (e.g. under `/tmp`, to stage a `gh ... --body-file` argument) is
never "source" and is exempt, because this rule only checks paths inside the
repo or worktree. (`technical-writer`'s docs-only rule is path-shape based and
still applies outside the repo.)

One boundary is intentionally *not* hook-enforced: whether the root session
should investigate a task itself or hand it to `project-orchestrator`. The
hook can't tell "an obvious one-line fix" apart from "an unclear bug report
that needs the source read and traced before a fix is even known" — that
call is left to the prompt guidance in `agents/project-orchestrator.md`'s
Scope rule and description examples. In short: skip the orchestrator only
when the right change is already obvious without digging into the code;
otherwise, diagnosis is the orchestrator's job (via `junior-engineer`), not
something to do directly first and hand off only once the answer is already
known.

## Adding this repo as a submodule

From the root of the repository you want Claude Code to use this
configuration in ("the main repo"):

```bash
git submodule add https://github.com/solwarsop/agentic-coding-harness.git .claude
git commit -m "Add agentic-coding-harness as .claude submodule"
```

Claude Code reads `.claude/agents/`, `.claude/skills/`, and
`.claude/settings.json` from the project root, so once the submodule is in
place its agents, skills, and settings apply automatically — no further
setup needed. Skills call the scripts in `scripts/` by relative path
(`.claude/scripts/...` from the project root, `../../scripts/...` from a
`.claude/worktrees/<name>` worktree).

## Cloning a main repo that already uses this submodule

Submodules are not checked out by a plain `git clone`. Either clone with:

```bash
git clone --recurse-submodules <main-repo-url>
```

or, if you already cloned without that flag:

```bash
git submodule update --init --recursive
```

## Updating the submodule

To pull in the latest changes from this repo into a main repo that
references it:

```bash
cd .claude
git pull origin main
cd ..
git add .claude
git commit -m "Update .claude submodule"
```

## Making changes to this configuration

Since `.claude` is a submodule, edits made inside it are commits against
*this* repository, not the main repo. Commit and push from within `.claude`
as usual, then commit the resulting submodule pointer update in the main
repo (as shown above).

## Testing prompt changes

After editing anything under `agents/` or `skills/`, run the maintainer A/B
test. It runs each case in `tests/prompt-ab/cases/` against two prompt sets
(the `--before` and `--after` refs, or `WORKTREE` for the working-tree files)
on a fixture project, several times each, and reports the pass rate of each
check for both sides:

```bash
scripts/prompt-ab-test.sh list
scripts/prompt-ab-test.sh run --before origin/main --after HEAD --runs 3
scripts/prompt-ab-test.sh report --before origin/main --after HEAD
```

`run` executes the sessions and then prints the report; `report` only rebuilds
it from saved scores. Use `--before origin/main` when local `main` may differ
from the remote. `--cases a,b` limits the cases, and `--dry-run` shows what is
done and what is still to run.

Every session calls the real `claude -p` and is billed as model usage. Runs
are resumable: rerunning the same command tops each side up to `--runs` and
skips runs that already have a score. If a usage or rate limit pauses the test,
the script exits with code 3; rerun the same command later to resume. A
timeout (`PROMPT_AB_TIMEOUT`, default 1200 seconds) or another error result is
scored as reported, with any check the checker could not evaluate counted as
failed, and listed under Errors in the report. A run whose setup or check
script fails is not scored at all.

Scores live under `tests/prompt-ab/results/<case>/<hash>/`, where `<hash>`
covers the prompt files (`agents/*.md` and `skills/**`). Each score also
records a `case_hash` of the test definition (case files, fixture, `lib.sh`
and the `gh` stub). A score with a different `case_hash` is moved to a
`stale-<timestamp>/` folder and ignored, so changed tests never mix with old
scores. Commit `score.json`, `meta.json` and `variants/`, so a paused test can
be resumed from another checkout; raw transcripts under `raw/` are gitignored.

A check is flagged `REGRESSION` when it passes in at least two thirds of the
before runs and fails in at least two thirds of the after runs. `IMPROVEMENT`
is the reverse.

Sessions run in a scratch copy of the fixture under `$TMPDIR`, each with its
own `--allowedTools` list. The `gh` stub comes first on `PATH`, `GH_CONFIG_DIR`
is empty and GitHub tokens are unset, so sessions get no GitHub credentials and
`gh` answers offline.
