"""Synthetic metric series generator, for demos and tests.

Produces a noisy baseline with an optional injected anomaly window
(sustained shift, not a single spike) so detectors have something
realistic to catch: a real incident is a step-change that persists, not
one noisy sample.
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta

from aiops.pipeline import MetricPoint


def generate_metric_series(
    entity: str,
    metric: str,
    start: datetime,
    count: int,
    interval_seconds: float,
    baseline: float,
    noise_std: float,
    anomaly_start_index: int | None = None,
    anomaly_end_index: int | None = None,
    anomaly_multiplier: float = 3.0,
    seed: int = 42,
) -> list[MetricPoint]:
    rng = random.Random(seed)
    points: list[MetricPoint] = []
    for i in range(count):
        timestamp = start + timedelta(seconds=i * interval_seconds)
        value = baseline + rng.gauss(0, noise_std)
        if (
            anomaly_start_index is not None
            and anomaly_end_index is not None
            and anomaly_start_index <= i < anomaly_end_index
        ):
            value = baseline * anomaly_multiplier + rng.gauss(0, noise_std)
        points.append(MetricPoint(entity=entity, metric=metric, value=max(value, 0.0), timestamp=timestamp))
    return points
