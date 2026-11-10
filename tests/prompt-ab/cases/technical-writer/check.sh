#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

check readme-mentions-json "README.md has no --json" grep -q -- '--json' README.md
if git status --porcelain | awk '{print $NF}' | grep -Eq '\.(py|toml)$'; then
  fail only-docs-changed "source/config file modified"
else pass only-docs-changed; fi
if [[ -z "$(git status --porcelain -- textstats tests pyproject.toml)" ]]; then pass source-untouched
else fail source-untouched "$(git status --porcelain -- textstats tests pyproject.toml | tr '\n' ' ')"; fi
check readme-reported "no README.md line in report" result_has 'README\.md`?:'
