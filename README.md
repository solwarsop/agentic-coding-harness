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

## Posting as a bot account instead of your own

By default, `git commit`/`gh` actions Claude Code runs locally are attributed
to whatever git/`gh` identity the environment already has — usually you. To
have Claude act as a separate bot account instead, `settings.json` wires a
`SessionStart` hook to `hooks/setup-bot-identity.sh`, which runs once at the
start of every session and sets up the bot's git/`gh` identity before any
commit or PR command runs.

This is opt-in and a no-op unless you supply bot credentials via environment
variables in the environment Claude Code runs in (export them locally, or set
them as repo/org secrets in CI — never commit real values):

- `CLAUDE_BOT_GIT_NAME` / `CLAUDE_BOT_GIT_EMAIL` — used for `git config
  user.name` / `user.email`, so commits are attributed to the bot.
- `CLAUDE_BOT_GH_TOKEN` — a PAT for the bot account. The hook runs `gh auth
  login --with-token` with it, so `gh pr create`, `gh pr comment`, etc. post
  as the bot instead of whatever `gh` was already logged in as.

`git config` and `gh auth login` both persist to files on disk, so unlike a
plain `export` (which the harness's own Bash tool does not carry across
separate tool invocations), the identity set up here holds for every
`git`/`gh` command for the rest of the session.

This only covers actions Claude runs itself via `git`/`gh` in a local or
cloud CLI session. It does not change who posts comments when Claude is
triggered through this repo's GitHub Actions workflow (`claude.yml`) — that
identity is controlled separately, by the `github_token`/`bot_id`/`bot_name`
inputs to `anthropics/claude-code-action` (see that action's docs).

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
