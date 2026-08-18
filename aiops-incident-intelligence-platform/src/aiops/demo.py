"""End-to-end demo: replays a synthetic cascading-failure scenario and a
synthetic resource-pressure scenario through the full pipeline, using an
isolated in-memory database, and prints what the platform produced.

Run with: ``python -m aiops.demo`` (or the ``aiops-demo`` console script).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.orm import sessionmaker

from aiops.anomaly.ml import IsolationForestDetector
from aiops.correlation.engine import Incident
from aiops.db import init_db, make_engine
from aiops.generators.scenario import cascading_failure_scenario, resource_pressure_scenario
from aiops.pipeline import AiopsPipeline
from aiops.remediation.rules import RemediationRule, RemediationRuleBook


def _fresh_session_factory():
    engine = make_engine("sqlite:///:memory:")
    init_db(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def _print_incident(incident: Incident) -> None:
    print(f"  {incident.id}  [{incident.severity:<8}]  root cause: {incident.probable_root_cause}")
    print(f"    entities: {', '.join(sorted(incident.entities))}")
    print(f"    signals ({incident.signal_count}):")
    for signal in incident.signals:
        print(f"      - [{signal.kind:<12}] {signal.entity}: {signal.description}")


def run_cascading_failure_demo() -> None:
    print("=" * 78)
    print("SCENARIO 1: cascading failure (db-primary -> orders-api -> checkout-web)")
    print("=" * 78)

    scenario = cascading_failure_scenario(start=datetime.now(UTC))
    rulebook = RemediationRuleBook(
        [
            RemediationRule(name="page-oncall-on-critical", action="notify_only", match_severity={"critical"}),
            RemediationRule(
                name="restart-on-repeated-error-logs",
                action="restart_service",
                match_severity={"critical", "error"},
                match_description_contains="log pattern",
            ),
        ]
    )
    pipeline = AiopsPipeline(
        dependency_graph=scenario.dependency_graph,
        remediation_rulebook=rulebook,
        session_factory=_fresh_session_factory(),
    )

    for point in scenario.metric_points:
        pipeline.ingest_metric(point)
    for line in scenario.log_lines:
        pipeline.ingest_log(line)

    incidents = pipeline.correlation.open_incidents + pipeline.correlation.closed_incidents
    print(f"\n{len(incidents)} incident(s) opened for {len(scenario.metric_points)} metric points "
          f"+ {len(scenario.log_lines)} log lines across 3 services:\n")
    for incident in sorted(incidents, key=lambda i: i.opened_at):
        _print_incident(incident)
        print()

    correct = any(
        incident.probable_root_cause == scenario.expected_root_cause for incident in incidents
    )
    print(f"Root cause correctly identified as '{scenario.expected_root_cause}': {correct}")


def run_resource_pressure_demo() -> None:
    print()
    print("=" * 78)
    print("SCENARIO 2: multivariate anomaly (cpu/queue-depth correlation inversion)")
    print("=" * 78)

    scenario = resource_pressure_scenario(start=datetime.now(UTC))
    detector = IsolationForestDetector(feature_names=scenario.feature_names)

    buffer: dict[str, float] = {}
    found_in_window = 0
    total_in_window = 0
    start_idx, end_idx = scenario.anomaly_index_range
    points_per_step = len(scenario.feature_names)

    for i, point in enumerate(scenario.metric_points):
        step = i // points_per_step
        buffer[point.metric] = point.value
        if len(buffer) < len(scenario.feature_names):
            continue
        result = detector.observe(scenario.entity, dict(buffer), point.timestamp)
        if start_idx <= step < end_idx:
            total_in_window += 1
            if result is not None:
                found_in_window += 1

    rate = found_in_window / total_in_window if total_in_window else 0.0
    print(f"\nFlagged {found_in_window}/{total_in_window} steps inside the injected anomaly "
          f"window ({rate:.0%}) -- each individual metric stayed within its normal range "
          f"the whole time.")


def main() -> None:
    run_cascading_failure_demo()
    run_resource_pressure_demo()


if __name__ == "__main__":
    main()
