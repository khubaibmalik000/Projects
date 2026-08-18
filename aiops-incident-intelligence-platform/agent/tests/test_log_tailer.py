from __future__ import annotations

from aiops_agent.log_tailer import LogTailer


def test_missing_file_returns_empty(tmp_path):
    tailer = LogTailer(tmp_path / "does-not-exist.log")
    assert tailer.read_new_lines() == []


def test_reads_only_lines_appended_since_last_call(tmp_path):
    path = tmp_path / "app.log"
    path.write_text("line1\nline2\n")

    tailer = LogTailer(path)
    assert tailer.read_new_lines() == ["line1", "line2"]
    assert tailer.read_new_lines() == []

    with path.open("a") as f:
        f.write("line3\n")
    assert tailer.read_new_lines() == ["line3"]


def test_blank_lines_are_skipped(tmp_path):
    path = tmp_path / "app.log"
    path.write_text("line1\n\n\nline2\n")

    tailer = LogTailer(path)
    assert tailer.read_new_lines() == ["line1", "line2"]


def test_truncated_file_restarts_from_beginning(tmp_path):
    path = tmp_path / "app.log"
    path.write_text("line1\nline2\nline3\n")

    tailer = LogTailer(path)
    tailer.read_new_lines()  # consume the initial content

    # simulate log rotation: file replaced with a shorter one
    path.write_text("new1\n")
    assert tailer.read_new_lines() == ["new1"]
