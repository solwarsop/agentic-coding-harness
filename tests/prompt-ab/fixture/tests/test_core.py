from textstats.core import line_count, top_words, word_count


def test_word_count() -> None:
    assert word_count("a b  c\nd") == 4


def test_line_count() -> None:
    assert line_count("a\nb\n") == 2


def test_top_words() -> None:
    assert top_words("a b a c a b", 2) == [("a", 3), ("b", 2)]
