"""Command-line interface for textstats."""

import argparse
from pathlib import Path

from textstats.core import line_count, word_count


def build_parser() -> argparse.ArgumentParser:
    """Build the argument parser for the textstats CLI."""
    parser = argparse.ArgumentParser(
        prog="textstats", description="Count words and lines in a file."
    )
    parser.add_argument("file", help="path to a text file")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the CLI and return the process exit code."""
    args = build_parser().parse_args(argv)
    text = Path(args.file).read_text(encoding="utf-8")
    print(f"words: {word_count(text)}")
    print(f"lines: {line_count(text)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
