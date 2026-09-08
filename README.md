# Agentic Coding Harness

Project-agnostic Claude Code configuration — custom agents, skills, and
settings — meant to be reused across multiple projects rather than
copy-pasted into each one.

This repo is designed to be added as a **git submodule at `.claude`** in a
host repository, so Claude Code picks it up automatically as that project's
configuration.

## Layout

- `agents/` — custom subagent definitions
- `skills/` — custom skills
- `settings.json` — shared Claude Code settings

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
