#!/usr/bin/env bash
# Tests scripts/delete-pushed-branch.sh against throwaway repos.
set -euo pipefail
script="$(cd "$(dirname "$0")/.." && pwd)/scripts/delete-pushed-branch.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/w" 2> /dev/null
cd "$tmp/w"
git checkout -q -b main; git commit -q --allow-empty -m base; git push -q origin main
fail=0
expect() { # expect <name> <want-rc> <cmd...>
  local name=$1 want=$2 rc=0; shift 2
  "$@" > /dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then echo "ok   $name"; else echo "FAIL $name (rc=$rc, want $want)"; fail=1; fi
}
# pushed but unmerged: deleted
git checkout -q -b pushed; git commit -q --allow-empty -m a; git push -q origin pushed; git checkout -q main
expect "pushed unmerged branch is deleted" 0 "$script" pushed
git show-ref --verify --quiet refs/heads/pushed && { echo "FAIL pushed still exists"; fail=1; }
# unpushed: refused
git checkout -q -b local; git commit -q --allow-empty -m b; git checkout -q main
expect "unpushed branch is refused" 1 "$script" local
git show-ref --verify --quiet refs/heads/local || { echo "FAIL local was deleted"; fail=1; }
# checked out: refused
git checkout -q -b pushed2; git push -q origin pushed2
expect "checked-out branch is refused" 1 "$script" pushed2
git checkout -q main
# missing / invalid
expect "missing branch is refused" 1 "$script" nope
expect "invalid name is rejected" 2 "$script" -D
expect "no args is usage error" 2 "$script"
exit "$fail"
