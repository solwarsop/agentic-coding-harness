#!/usr/bin/env bash
# SessionStart hook: makes git commits and gh CLI actions (PRs, comments) run
# as a separate bot account instead of whichever human/CI identity the
# session inherited, when bot credentials are supplied via environment
# variables. This is opt-in and a no-op if none of the variables below are
# set, since this repo is shared as a submodule across projects that may not
# want a bot identity at all.
#
# Host project setup: export these (e.g. as repo/org secrets passed into the
# environment Claude Code runs in) before starting a session. Do not commit
# real values here — this script only reads them.
#   CLAUDE_BOT_GIT_NAME  - git user.name used for commits
#   CLAUDE_BOT_GIT_EMAIL - git user.email used for commits
#   CLAUDE_BOT_GH_TOKEN  - PAT for the bot account; authenticates the gh CLI
#                          so `gh pr create`/`gh pr comment`/etc. post as the
#                          bot instead of the token gh was already logged in
#                          with
#
# git config and `gh auth login` both persist to files on disk (.git/config
# and the gh config directory), so unlike a plain `export` they survive
# across the separate shell processes each Bash tool call runs in.
set -euo pipefail

if [ -n "${CLAUDE_BOT_GIT_NAME:-}" ]; then
  git config user.name "$CLAUDE_BOT_GIT_NAME"
fi

if [ -n "${CLAUDE_BOT_GIT_EMAIL:-}" ]; then
  git config user.email "$CLAUDE_BOT_GIT_EMAIL"
fi

if [ -n "${CLAUDE_BOT_GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  echo "$CLAUDE_BOT_GH_TOKEN" | gh auth login --with-token
fi

exit 0
