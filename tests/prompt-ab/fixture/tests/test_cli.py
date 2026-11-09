from pathlib import Path

import pytest

from textstats.cli import main


def test_main_prints_counts(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    f = tmp_path / "in.txt"
    f.write_text("one two\nthree\n", encoding="utf-8")
    assert main([str(f)]) == 0
    out = capsys.readouterr().out
    assert "words: 3" in out
    assert "lines: 2" in out
