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
`software-engineer` never touches docs/plans) are enforced technically, not
just by prompt text: `settings.json` wires a `PreToolUse` hook to
`hooks/enforce-agent-boundaries.sh`, which reads each tool call's
`agent_type`/`agent_id` and denies calls outside an agent's declared scope.
Scope is matched on path shape rather than on top-level directories alone, so
nested documentation is classified like its top-level counterpart: `docs/` and
`plans/` match at any depth, and a `README.md`/`CLAUDE.md` in a subdirectory
(e.g. `pipelines/README.md`) counts as documentation/plan just as the root one
does. `project-orchestrator` may read any Markdown file — Markdown is
documentation, not source — plus non-Markdown assets under `docs/` or `plans/`;
everything else still has to come back as a `software-engineer` summary.

The same hook also denies a root/coordinating session from editing source
directly while it's working inside a `.claude/worktrees/` checkout (i.e.
mid-flight on a worktree-owning skill like `custom-agent-plan`) — a root
session working in the normal repo path is unaffected.

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
