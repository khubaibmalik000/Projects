from __future__ import annotations

from datetime import datetime, timedelta

from aiops.correlation.dependency_graph import ServiceDependencyGraph
from aiops.correlation.engine import CorrelationEngine, Signal


def _ts(seconds: int) -> datetime:
    return datetime(2026, 1, 1) + timedelta(seconds=seconds)


def _signal(entity: str, seconds: int, severity: str = "warning") -> Signal:
    return Signal(
        entity=entity,
        kind="metric",
        description=f"anomaly on {entity}",
        severity=severity,
        score=4.0,
        timestamp=_ts(seconds),
    )


def test_related_signals_within_window_merge_into_one_incident():
    graph = ServiceDependencyGraph([("db", "api")])
    engine = CorrelationEngine(dependency_graph=graph, correlation_window_seconds=60)

    engine.ingest(_signal("db", 0))
    incident = engine.ingest(_signal("api", 10))

    assert len(engine.open_incidents) == 1
    assert incident.signal_count == 2
    assert incident.entities == {"db", "api"}


def test_unrelated_signals_open_separate_incidents():
    engine = CorrelationEngine(dependency_graph=ServiceDependencyGraph())

    engine.ingest(_signal("db", 0))
    engine.ingest(_signal("unrelated-worker", 1))

    assert len(engine.open_incidents) == 2


def test_signals_outside_window_do_not_merge():
    graph = ServiceDependencyGraph([("db", "api")])
    # close_after_seconds set well beyond the gap so the first incident is
    # still open (not auto-expired) when the second signal arrives -- this
    # isolates "outside the correlation window" from "incident expired".
    engine = CorrelationEngine(
        dependency_graph=graph, correlation_window_seconds=30, close_after_seconds=1000
    )

    engine.ingest(_signal("db", 0))
    engine.ingest(_signal("api", 500))  # beyond the 30s correlation window

    assert len(engine.open_incidents) == 2


def test_root_cause_is_the_most_upstream_affected_entity():
    graph = ServiceDependencyGraph([("db", "api"), ("api", "web")])
    engine = CorrelationEngine(dependency_graph=graph, correlation_window_seconds=120)

    engine.ingest(_signal("web", 10))
    engine.ingest(_signal("api", 5))
    incident = engine.ingest(_signal("db", 0))

    assert incident.probable_root_cause == "db"


def test_incident_severity_is_the_worst_signal_severity():
    engine = CorrelationEngine()
    engine.ingest(_signal("svc", 0, severity="warning"))
    incident = engine.ingest(_signal("svc", 1, severity="critical"))
    assert incident.severity == "critical"


def test_stale_incident_closes_after_close_after_seconds():
    engine = CorrelationEngine(correlation_window_seconds=60, close_after_seconds=100)
    engine.ingest(_signal("svc", 0))
    assert len(engine.open_incidents) == 1

    engine.close_stale(_ts(200))
    assert len(engine.open_incidents) == 0
    assert len(engine.closed_incidents) == 1
    assert engine.closed_incidents[0].status == "closed"
