"""A canned cascading-failure scenario used by the demo script and the
correlation/root-cause tests: a database goes slow, which a few seconds
later shows up as an error-rate spike in the API that queries it, which a
few seconds after that shows up as elevated latency in the web tier that
calls the API. One root cause, three affected services, three-plus
independent anomaly signals -- the exact shape alert correlation exists for.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from datetime import datetime, timedelta

from aiops.correlation.dependency_graph import ServiceDependencyGraph
from aiops.generators.log_generator import generate_log_lines
from aiops.generators.metric_generator import generate_metric_series
from aiops.pipeline import LogLine, MetricPoint

DB = "db-primary"
API = "orders-api"
WEB = "checkout-web"


@dataclass
class ScenarioResult:
    metric_points: list[MetricPoint]
    log_lines: list[LogLine]
    dependency_graph: ServiceDependencyGraph
    expected_root_cause: str


def cascading_failure_scenario(
    start: datetime, count: int = 120, interval_seconds: float = 2.0, seed: int = 42
) -> ScenarioResult:
    graph = ServiceDependencyGraph([(DB, API), (API, WEB)])

    metric_points: list[MetricPoint] = []
    metric_points += generate_metric_series(
        DB, "query_latency_ms", start, count, interval_seconds,
        baseline=20.0, noise_std=2.0,
        anomaly_start_index=60, anomaly_end_index=90, anomaly_multiplier=8.0, seed=seed,
    )
    metric_points += generate_metric_series(
        API, "error_rate", start, count, interval_seconds,
        baseline=0.5, noise_std=0.1,
        anomaly_start_index=63, anomaly_end_index=93, anomaly_multiplier=15.0, seed=seed + 1,
    )
    metric_points += generate_metric_series(
        WEB, "p95_latency_ms", start, count, interval_seconds,
        baseline=300.0, noise_std=20.0,
        anomaly_start_index=66, anomaly_end_index=96, anomaly_multiplier=4.0, seed=seed + 2,
    )
    metric_points.sort(key=lambda p: p.timestamp)

    log_lines: list[LogLine] = []
    log_lines += generate_log_lines(
        DB, start, count, interval_seconds,
        error_start_index=60, error_end_index=90, seed=seed,
    )
    log_lines += generate_log_lines(
        API, start, count, interval_seconds,
        error_start_index=63, error_end_index=93, seed=seed + 1,
    )
    log_lines.sort(key=lambda line: line.timestamp)

    return ScenarioResult(
        metric_points=metric_points,
        log_lines=log_lines,
        dependency_graph=graph,
        expected_root_cause=DB,
    )


@dataclass
class ResourcePressureScenario:
    entity: str
    feature_names: list[str]
    metric_points: list[MetricPoint]
    anomaly_index_range: tuple[int, int]


def resource_pressure_scenario(
    start: datetime, count: int = 200, interval_seconds: float = 5.0, seed: int = 7
) -> ResourcePressureScenario:
    """A worker whose CPU and queue depth are normally *anti-correlated*
    (busier workers drain the queue faster) starts showing both rising
    together -- individually each value stays inside its normal range, so
    a per-metric z-score never fires, but the joint pattern is off the
    manifold the Isolation Forest learned. Demonstrates why the platform
    needs a multivariate detector alongside the univariate one.
    """
    entity = "payments-worker-7"
    rng = random.Random(seed)
    anomaly_start, anomaly_end = int(count * 0.65), int(count * 0.80)

    metric_points: list[MetricPoint] = []
    for i in range(count):
        timestamp = start + timedelta(seconds=i * interval_seconds)
        factor = rng.gauss(0, 1)
        cpu = 50 + 10 * factor + rng.gauss(0, 2)
        if anomaly_start <= i < anomaly_end:
            queue = 10 + 3 * factor + rng.gauss(0, 1)  # correlation flips: high cpu no longer drains the queue
        else:
            queue = 10 - 3 * factor + rng.gauss(0, 1)
        metric_points.append(MetricPoint(entity, "cpu_percent", max(cpu, 0.0), timestamp))
        metric_points.append(MetricPoint(entity, "queue_depth", max(queue, 0.0), timestamp))

    return ResourcePressureScenario(
        entity=entity,
        feature_names=["cpu_percent", "queue_depth"],
        metric_points=metric_points,
        anomaly_index_range=(anomaly_start, anomaly_end),
    )
