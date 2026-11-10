#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

check pytest-pass "pytest failed" pytest -q
check ruff-pass "ruff check failed" ruff check .

if git diff HEAD -- tests/ | grep -Eq '^\+\s*def test_\w*' &&
  git diff HEAD -- tests/ | grep -E '^\+' | grep -Eq -- '--json'; then pass test-added
else fail test-added "no new test function exercising --json in tests/"; fi

if bad=$(python3 - <<'PY'
import ast, pathlib, subprocess, sys
status = subprocess.run(["git", "status", "--porcelain", "-uall", "--", "textstats"],
                        capture_output=True, text=True, check=True).stdout.splitlines()
changed = [line[3:] for line in status if line.endswith(".py")]
bad = []
for f in changed:
    p = pathlib.Path(f)
    if not p.exists():
        continue
    for node in ast.walk(ast.parse(p.read_text())):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and not node.name.startswith("_"):
            if not ast.get_docstring(node):
                bad.append(f"{f}:{node.name}")
print(",".join(bad))
sys.exit(1 if bad else 0)
PY
); then pass docstring; else fail docstring "missing: $bad"; fi

if [[ -z "$(git status --porcelain -- README.md docs)" ]]; then pass no-doc-edits; else fail no-doc-edits "README.md or docs/ changed"; fi

tmp=$(mktemp)
printf 'one two\nthree\n' >"$tmp"
if out=$(python3 -m textstats.cli --json "$tmp" 2>&1) &&
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d=={"words":3,"lines":2}, d' "$out" 2>/dev/null; then
  pass json-works
else fail json-works "bad output: ${out:0:80}"; fi
rm -f "$tmp"
