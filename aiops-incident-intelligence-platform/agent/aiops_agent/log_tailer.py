"""Tails a log file, returning only lines appended since the last read."""

from __future__ import annotations

from pathlib import Path


class LogTailer:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self._offset = 0

    def read_new_lines(self) -> list[str]:
        if not self.path.exists():
            return []

        size = self.path.stat().st_size
        if size < self._offset:
            # File shrank -- rotated or truncated. Start over rather than
            # erroring or seeking past the end.
            self._offset = 0

        with self.path.open("r", encoding="utf-8", errors="replace") as f:
            f.seek(self._offset)
            chunk = f.read()
            self._offset = f.tell()

        return [line for line in chunk.splitlines() if line.strip()]
