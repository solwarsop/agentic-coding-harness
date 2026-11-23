#!/usr/bin/env bash
# Force-delete a local branch only if its tip is reachable from a branch on origin (pushed, merged or not).
# Usage: ../../scripts/delete-pushed-branch.sh <branch>
# Exit 0 deleted, 1 refused (unpushed commits, checked-out branch, missing branch, fetch failure), 2 usage.
# Never touches the remote. From the project root use .claude/scripts/delete-pushed-branch.sh.
set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: $0 <branch>" >&2; exit 2; }
branch=$1
[[ "$branch" =~ ^[A-Za-z0-9._/-]+$ && "$branch" != -* ]] || { echo "error: invalid branch name" >&2; exit 2; }

git show-ref --verify --quiet "refs/heads/$branch" || { echo "refused: no local branch '$branch'" >&2; exit 1; }

# Refuse a branch checked out in any worktree.
if git worktree list --porcelain | grep -qxF "branch refs/heads/$branch"; then
  echo "refused: '$branch' is checked out in a worktree" >&2
  exit 1
fi

git fetch --quiet --prune origin || { echo "refused: git fetch origin failed" >&2; exit 1; }

tip=$(git rev-parse --verify "refs/heads/$branch^{commit}")
if [ -z "$(git for-each-ref --contains "$tip" --format='%(refname)' refs/remotes/origin)" ]; then
  echo "refused: '$branch' has commits not on any origin branch:" >&2
  git log --oneline "$tip" --not --remotes=origin >&2
  exit 1
fi

git branch -D -- "$branch"
