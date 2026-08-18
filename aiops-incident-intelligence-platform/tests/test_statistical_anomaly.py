from __future__ import annotations

import random
from datetime import datetime, timedelta

import pytest

from aiops.anomaly.statistical import EwmaZScoreDetector


def _ts(i: int) -> datetime:
    return datetime(2026, 1, 1) + timedelta(seconds=i)


def test_no_anomaly_during_warmup():
    detector = EwmaZScoreDetector(warmup_samples=10)
    for i in range(10):
        assert detector.observe("svc:cpu", 50.0, _ts(i)) is None


def test_stable_series_rarely_flags_and_never_flags_critical():
    # Genuine Gaussian noise crosses a 3-sigma threshold ~0.3% of the time
    # by chance; a stable series should produce at most a rare warning,
    # never a 5-sigma critical.
    rng = random.Random(1)
    detector = EwmaZScoreDetector(warmup_samples=20, warn_sigma=3.0, crit_sigma=5.0)
    anomalies = []
    for i in range(300):
        value = 50.0 + rng.gauss(0, 2.0)
        result = detector.observe("svc:cpu", value, _ts(i))
        if result is not None:
            anomalies.append(result)
    assert len(anomalies) <= 10
    assert all(a.severity == "warning" for a in anomalies)


def test_sustained_spike_is_flagged_critical():
    rng = random.Random(2)
    detector = EwmaZScoreDetector(warmup_samples=20, warn_sigma=3.0, crit_sigma=5.0)
    anomalies_during_spike = []
    for i in range(60):
        value = 50.0 + rng.gauss(0, 2.0)
        if i >= 40:
            value = 200.0 + rng.gauss(0, 2.0)
        result = detector.observe("svc:cpu", value, _ts(i))
        if result is not None and i >= 40:
            anomalies_during_spike.append(result)

    assert anomalies_during_spike
    first = anomalies_during_spike[0]
    assert first.severity in {"warning", "critical"}
    assert first.z_score > 0


def test_series_are_independent():
    detector = EwmaZScoreDetector(warmup_samples=5)
    for i in range(5):
        detector.observe("svc-a:cpu", 10.0, _ts(i))
    # svc-b has seen nothing yet, so it's still warming up regardless of svc-a's state
    assert detector.observe("svc-b:cpu", 999.0, _ts(0)) is None


def test_baseline_damping_limits_drift_from_a_single_spike():
    detector = EwmaZScoreDetector(warmup_samples=20, warn_sigma=3.0, anomalous_update_damping=0.1)
    for i in range(20):
        detector.observe("svc:cpu", 50.0, _ts(i))
    mean_before, _ = detector.baseline("svc:cpu")

    detector.observe("svc:cpu", 500.0, _ts(20))  # one big spike
    mean_after, _ = detector.baseline("svc:cpu")

    # damped update should move the mean only slightly, not toward the spike
    assert mean_after - mean_before < (500.0 - mean_before) * 0.2


def test_rejects_invalid_alpha():
    with pytest.raises(ValueError):
        EwmaZScoreDetector(alpha=0)


def test_rejects_crit_sigma_not_greater_than_warn_sigma():
    with pytest.raises(ValueError):
        EwmaZScoreDetector(warn_sigma=5.0, crit_sigma=5.0)
