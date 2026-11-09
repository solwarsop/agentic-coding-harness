"""Core counting functions for textstats."""

from collections import Counter


def word_count(text: str) -> int:
    """Return the number of whitespace-separated words in text."""
    return len(text.split())


def line_count(text: str) -> int:
    """Return the number of lines in text (a trailing newline adds none)."""
    return len(text.splitlines())


def top_words(text: str, n: int) -> list[tuple[str, int]]:
    """Return the n most common words (lowercased) with their counts."""
    counts = Counter(word.lower() for word in text.split())
    return counts.most_common(n)
