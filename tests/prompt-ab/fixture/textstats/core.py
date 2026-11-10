"""Core counting functions for textstats."""


def word_count(text: str) -> int:
    """Return the number of whitespace-separated words in text."""
    return len(text.split())


def line_count(text: str) -> int:
    """Return the number of lines in text (a trailing newline adds none)."""
    return len(text.splitlines())


def top_words(text: str, n: int) -> list[tuple[str, int]]:
    """Return the n most common words (lowercased) with their counts."""
    words = [word.lower() for word in text.split()]
    unique = list(dict.fromkeys(words))
    unique.sort(key=words.count, reverse=True)
    return [(word, words.count(word)) for word in unique[:n]]
