#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

check pytest-pass "pytest failed" pytest -q
check ruff-pass "ruff check failed" ruff check .

check item1-done "help text not changed" grep -qF 'path to a UTF-8 text file' textstats/cli.py

if git diff --quiet HEAD -- pyproject.toml && ! grep -Eq '^\s*(import|from) click' textstats/cli.py; then pass click-not-ported
else fail click-not-ported "pyproject.toml changed or cli.py imports click"; fi

if result_has_i 'click' && result_has_i 'skip|much costlier|costlier than briefed|not (done|implemented|ported)|demot|follow-up'; then
  pass skip-reported
else fail skip-reported "final report does not list the click port as skipped"; fi

if [[ -z "$(git status --porcelain -- README.md docs)" ]]; then pass no-doc-edits; else fail no-doc-edits "README.md or docs/ changed"; fi
