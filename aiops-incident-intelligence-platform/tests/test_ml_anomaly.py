from __future__ import annotations

import random
from datetime import datetime, timedelta

import pytest

from aiops.anomaly.ml import IsolationForestDetector


def _ts(i: int) -> datetime:
    return datetime(2026, 1, 1) + timedelta(seconds=i)


def test_returns_none_before_min_samples():
    detector = IsolationForestDetector(feature_names=["a", "b"], min_samples_to_fit=30)
    for i in range(29):
        assert detector.observe("entity", {"a": 1.0, "b": 1.0}, _ts(i)) is None


def test_missing_feature_raises():
    detector = IsolationForestDetector(feature_names=["a", "b"])
    with pytest.raises(KeyError):
        detector.observe("entity", {"a": 1.0}, _ts(0))


def test_flags_outlier_off_the_correlation_manifold():
    """cpu and queue_depth are anti-correlated in normal operation; a run
    where they move *together* is a multivariate outlier even though each
    value, taken alone, is well within its historical range.
    """
    rng = random.Random(7)
    detector = IsolationForestDetector(
        feature_names=["cpu_percent", "queue_depth"],
        window_size=150,
        min_samples_to_fit=40,
        retrain_interval=20,
        contamination=0.05,
    )

    flags_in_normal_region = 0
    flags_in_anomaly_region = 0
    for i in range(180):
        factor = rng.gauss(0, 1)
        cpu = 50 + 10 * factor + rng.gauss(0, 2)
        in_anomaly_region = 140 <= i < 170
        queue = (10 + 3 * factor if in_anomaly_region else 10 - 3 * factor) + rng.gauss(0, 1)

        result = detector.observe(
            "worker", {"cpu_percent": max(cpu, 0), "queue_depth": max(queue, 0)}, _ts(i)
        )
        if result is not None:
            if in_anomaly_region:
                flags_in_anomaly_region += 1
            else:
                flags_in_normal_region += 1

    anomaly_region_size = 170 - 140
    normal_region_size = 180 - anomaly_region_size
    hit_rate = flags_in_anomaly_region / anomaly_region_size
    false_positive_rate = flags_in_normal_region / normal_region_size

    assert flags_in_anomaly_region > 0
    # the anomaly-region hit rate should clearly exceed the baseline
    # false-positive rate from contamination=0.05 on in-distribution data
    assert hit_rate > false_positive_rate * 2


def test_contributing_features_are_reported():
    # Isolation Forest splits are range-bound to the training data at each
    # tree node, so an extreme single-feature outlier isn't reliably
    # isolated from a tiny training set diluted by noise dimensions --
    # this needs enough normal history for the model to have a stable
    # notion of "normal" before the anomaly starts.
    rng = random.Random(3)
    detector = IsolationForestDetector(
        feature_names=["a", "b"], window_size=200, min_samples_to_fit=100, retrain_interval=20
    )
    result = None
    for i in range(140):
        vec = {"a": 10 + rng.gauss(0, 1), "b": 10 + rng.gauss(0, 1)}
        if i >= 110:
            vec["a"] = 1000.0
        result = detector.observe("entity", vec, _ts(i))
        if result is not None:
            break

    assert result is not None
    assert next(iter(result.contributing_features)) == "a"
