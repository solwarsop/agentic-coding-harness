Implement a `--json` flag for the textstats CLI (`textstats/cli.py`).

Exact behaviour: `textstats --json <file>` prints a single JSON object on one line, `{"words": <n>, "lines": <n>}`, using the same counts as the default output. Without `--json` the plain-text output is unchanged. The flag must appear in `--help`.

Testing scope: tests ARE in scope. Add a test for the new flag to `tests/test_cli.py`; keep the existing tests passing.

Constraints: do not touch README.md or anything under docs/. Do not commit. Run `ruff check .` and `pytest -q` before finishing.
