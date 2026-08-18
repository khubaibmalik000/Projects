"""Univariate anomaly detection over streaming metric series.

Combines a Welford warmup phase (stable mean/variance from the first
samples) with a steady-state EWMA model (adapts to slow drift/seasonality
without needing to store history).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from math import sqrt
from typing import Literal

Severity = Literal["warning", "critical"]


@dataclass
class StatisticalAnomaly:
    series_key: str
    value: float
    baseline_mean: float
    baseline_std: float
    z_score: float
    severity: Severity
    timestamp: datetime


@dataclass
class _SeriesState:
    count: int = 0
    mean: float = 0.0
    var: float = 0.0
    m2: float = 0.0  # Welford accumulator, warmup phase only


class EwmaZScoreDetector:
    """Per-series z-score anomaly detector with an EWMA baseline.

    One instance tracks many independent series, keyed by an arbitrary
    string (e.g. ``"checkout-api:latency_ms"``).

    ``alpha`` trades adaptation speed against false-positive rate: with
    only ~5-6 effective samples of memory (2/alpha - 1) at the default
    EWMA-textbook alpha of 0.3, the *variance* estimate itself is noisy
    enough that stable Gaussian noise trips a 3-sigma threshold far more
    than the naive ~0.3%-per-sample rate would suggest. The default here
    (0.1, ~19 effective samples) trades a slower reaction to genuine
    drift for a much lower false-positive rate on real, moderately noisy
    infra metrics.
    """

    def __init__(
        self,
        alpha: float = 0.1,
        warmup_samples: int = 20,
        warn_sigma: float = 3.0,
        crit_sigma: float = 5.0,
        min_std: float = 1e-6,
        anomalous_update_damping: float = 0.1,
    ) -> None:
        if not 0 < alpha <= 1:
            raise ValueError("alpha must be in (0, 1]")
        if warn_sigma <= 0 or crit_sigma <= warn_sigma:
            raise ValueError("crit_sigma must be greater than warn_sigma > 0")
        self.alpha = alpha
        self.warmup_samples = warmup_samples
        self.warn_sigma = warn_sigma
        self.crit_sigma = crit_sigma
        self.min_std = min_std
        self.anomalous_update_damping = anomalous_update_damping
        self._state: dict[str, _SeriesState] = {}

    def observe(
        self, series_key: str, value: float, timestamp: datetime
    ) -> StatisticalAnomaly | None:
        state = self._state.setdefault(series_key, _SeriesState())
        state.count += 1

        if state.count <= self.warmup_samples:
            self._update_warmup(state, value)
            return None

        std = max(sqrt(state.var), self.min_std)
        z = (value - state.mean) / std

        anomaly: StatisticalAnomaly | None = None
        if abs(z) >= self.crit_sigma:
            anomaly = StatisticalAnomaly(
                series_key, value, state.mean, std, z, "critical", timestamp
            )
        elif abs(z) >= self.warn_sigma:
            anomaly = StatisticalAnomaly(
                series_key, value, state.mean, std, z, "warning", timestamp
            )

        # Dampen the baseline update on anomalous points so a real spike
        # doesn't drag the mean toward it and mask the next occurrence.
        effective_alpha = (
            self.alpha if anomaly is None else self.alpha * self.anomalous_update_damping
        )
        diff = value - state.mean
        state.mean += effective_alpha * diff
        state.var = (1 - effective_alpha) * (state.var + effective_alpha * diff * diff)

        return anomaly

    def _update_warmup(self, state: _SeriesState, value: float) -> None:
        delta = value - state.mean
        state.mean += delta / state.count
        delta2 = value - state.mean
        state.m2 += delta * delta2
        if state.count > 1:
            state.var = state.m2 / (state.count - 1)

    def baseline(self, series_key: str) -> tuple[float, float] | None:
        state = self._state.get(series_key)
        if state is None or state.count < 2:
            return None
        return state.mean, max(sqrt(state.var), self.min_std)

    def reset(self, series_key: str | None = None) -> None:
        if series_key is None:
            self._state.clear()
        else:
            self._state.pop(series_key, None)
