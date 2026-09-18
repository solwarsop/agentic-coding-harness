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

The same hook also denies a root/coordinating session from editing source
directly while it's working inside a `.claude/worktrees/` checkout (i.e.
mid-flight on a worktree-owning skill like `custom-agent-plan`) — a root
session working in the normal repo path is unaffected. This restriction only
applies to paths inside the repo/worktree itself: a scratch file written
outside it (e.g. under `/tmp`, to stage a `gh ... --body-file` argument) is
never "source" and is exempt, per `custom-agent-plan`'s Body-file convention.

The hook also guards Bash calls for `project-orchestrator`, `senior-engineer`,
and `technical-writer` (in addition to its existing Edit/Write/NotebookEdit
guards), using a heuristic backstop to extract and classify path-like tokens
from the command string — same posture as `code-reviewer`'s existing Bash
guard. This backstop can be fooled by unusual quoting, chained commands after
`&&`, or paths without a recognized extension, so it is not a sandbox, only a
guard against obvious oversights. The rules differ per agent: `project-orchestrator`
denies any access (read or write) to non-Markdown source, matching its Read
restriction; `senior-engineer` and `technical-writer` allow read-only Bash
inspection (via `cat`, `grep`, etc.) but deny mutating commands (`sed -i`,
`mv`, `rm`, `cp`, `tee`, `truncate`, bare `>` redirects) on restricted paths,
matching what their dedicated Read tool already allows. Scratch paths outside
the repo are universally exempt from these guards.

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
setup needed.

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
