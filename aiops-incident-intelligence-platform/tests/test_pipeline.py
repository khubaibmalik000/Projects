from __future__ import annotations

from datetime import UTC, datetime

from aiops.generators.scenario import cascading_failure_scenario
from aiops.pipeline import AiopsPipeline, LogLine
from aiops.remediation.rules import RemediationRule, RemediationRuleBook
from aiops.repository import list_incidents


def test_normal_log_line_produces_no_incident(session_factory):
    pipeline = AiopsPipeline(session_factory=session_factory)
    incident = pipeline.ingest_log(
        LogLine(entity="svc", message="healthcheck ok uptime_s=42", timestamp=datetime.now(UTC))
    )
    assert incident is None


def test_cascading_scenario_identifies_root_cause_and_persists(session_factory):
    scenario = cascading_failure_scenario(start=datetime.now(UTC))
    rulebook = RemediationRuleBook(
        [RemediationRule(name="page", action="notify_only", match_severity={"critical"})]
    )
    pipeline = AiopsPipeline(
        dependency_graph=scenario.dependency_graph,
        remediation_rulebook=rulebook,
        session_factory=session_factory,
    )

    for point in scenario.metric_points:
        pipeline.ingest_metric(point)
    for line in scenario.log_lines:
        pipeline.ingest_log(line)

    incidents = pipeline.correlation.open_incidents + pipeline.correlation.closed_incidents
    assert len(incidents) >= 1
    assert any(i.probable_root_cause == scenario.expected_root_cause for i in incidents)

    with session_factory() as session:
        records = list_incidents(session, limit=100)
    assert len(records) == len(incidents)
    persisted_ids = {r.id for r in records}
    assert persisted_ids == {i.id for i in incidents}

    # at least one persisted incident carries multiple signals from more than one service
    multi_entity = [r for r in records if len(r.entities) > 1]
    assert multi_entity, "expected correlation to merge related-service signals into one incident"
