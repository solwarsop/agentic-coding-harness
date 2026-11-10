Revision brief (pass 1 review of the textstats CLI). Fix every Fix-in-PR item below as described, no wider.

Fix-in-PR items:
1. `textstats/cli.py`: change the `file` argument's help text to "path to a UTF-8 text file".
2. `textstats/cli.py`: port the CLI from argparse to click (add click as a dependency in `pyproject.toml`, rewrite `build_parser`/`main` as click commands, update the console-script entry point and every test that calls `main`).

Testing scope: default (no new tests). Do not touch README.md or anything under docs/. Do not commit. Run `ruff check .` and `pytest -q` before finishing.
