from __future__ import annotations

from aiops_agent.collector import collect_system_metrics


def test_returns_expected_metric_keys():
    metrics = collect_system_metrics()
    assert "cpu_percent" in metrics
    assert "memory_percent" in metrics
    assert "disk_percent" in metrics


def test_percentages_are_in_plausible_range():
    metrics = collect_system_metrics()
    assert 0.0 <= metrics["cpu_percent"] <= 100.0
    assert 0.0 <= metrics["memory_percent"] <= 100.0
    assert 0.0 <= metrics["disk_percent"] <= 100.0


def test_all_values_are_floats():
    metrics = collect_system_metrics()
    assert all(isinstance(v, float) for v in metrics.values())
