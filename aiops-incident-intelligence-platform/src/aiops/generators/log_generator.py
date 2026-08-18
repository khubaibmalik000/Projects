"""Synthetic log line generator: a pool of normal templates plus an injected
burst of a rare/new error template within a chosen index window.
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta

from aiops.pipeline import LogLine

_NORMAL_TEMPLATES = [
    "request completed method=GET path=/api/v1/orders status=200 duration_ms={n}",
    "request completed method=POST path=/api/v1/cart status=201 duration_ms={n}",
    "cache hit key=session:{n}",
    "healthcheck ok uptime_s={n}",
]

_ERROR_TEMPLATES = [
    "ERROR connection to db-primary refused after {n}ms, retrying",
    "ERROR upstream payments-api timed out after {n}ms",
    "FATAL out of memory: heap allocation of {n} bytes failed",
]


def generate_log_lines(
    entity: str,
    start: datetime,
    count: int,
    interval_seconds: float,
    error_start_index: int | None = None,
    error_end_index: int | None = None,
    seed: int = 42,
) -> list[LogLine]:
    rng = random.Random(seed)
    lines: list[LogLine] = []
    for i in range(count):
        timestamp = start + timedelta(seconds=i * interval_seconds)
        in_error_window = (
            error_start_index is not None
            and error_end_index is not None
            and error_start_index <= i < error_end_index
        )
        template_pool = _ERROR_TEMPLATES if in_error_window else _NORMAL_TEMPLATES
        template = rng.choice(template_pool)
        message = template.format(n=rng.randint(1, 5000))
        lines.append(LogLine(entity=entity, message=message, timestamp=timestamp))
    return lines
