from __future__ import annotations

from datetime import datetime, timedelta

from aiops.correlation.engine import Incident, Signal
from aiops.remediation.executor import ActionOutcome, RemediationExecutor, default_registry
from aiops.remediation.rules import RemediationRule, RemediationRuleBook


def _ts(seconds: int) -> datetime:
    return datetime(2026, 1, 1) + timedelta(seconds=seconds)


def _incident(entity: str, seconds: int, severity: str = "critical", description: str = "spike") -> Incident:
    signal = Signal(
        entity=entity, kind="metric", description=description, severity=severity,
        score=5.0, timestamp=_ts(seconds),
    )
    return Incident(
        id="INC-1", signals=[signal], entities={entity},
        opened_at=_ts(seconds), last_seen_at=_ts(seconds), probable_root_cause=entity,
    )


def test_no_matching_rule_returns_none():
    rulebook = RemediationRuleBook([RemediationRule(name="r1", action="notify_only", match_severity={"critical"})])
    executor = RemediationExecutor(rulebook)
    result = executor.handle(_incident("svc", 0, severity="warning"))
    assert result is None


def test_matching_rule_fires_in_dry_run_by_default():
    rulebook = RemediationRuleBook([RemediationRule(name="page", action="notify_only", match_severity={"critical"})])
    executor = RemediationExecutor(rulebook)
    result = executor.handle(_incident("svc", 0))
    assert result is not None
    assert result.dry_run is True
    assert result.outcome.success is True
    assert "DRY RUN" in result.outcome.message


def test_live_mode_executes_without_dry_run_prefix():
    rulebook = RemediationRuleBook([RemediationRule(name="page", action="notify_only", match_severity={"critical"})])
    executor = RemediationExecutor(rulebook, dry_run=False)
    result = executor.handle(_incident("svc", 0))
    assert result.dry_run is False
    assert "DRY RUN" not in result.outcome.message


def test_cooldown_suppresses_repeat_firing():
    rulebook = RemediationRuleBook(
        [RemediationRule(name="page", action="notify_only", match_severity={"critical"}, cooldown_seconds=300)]
    )
    executor = RemediationExecutor(rulebook)

    incident = _incident("svc", 0)
    first = executor.handle(incident)
    assert first is not None

    incident.last_seen_at = _ts(60)  # only 60s later, inside the 300s cooldown
    second = executor.handle(incident)
    assert second is None

    incident.last_seen_at = _ts(400)  # past the cooldown
    third = executor.handle(incident)
    assert third is not None


def test_entity_prefix_and_description_filters():
    rulebook = RemediationRuleBook(
        [
            RemediationRule(
                name="restart-db",
                action="restart_service",
                match_entity_prefix="db-",
                match_description_contains="log pattern",
            )
        ]
    )
    executor = RemediationExecutor(rulebook)

    assert executor.handle(_incident("api-1", 0, description="log pattern: ERROR")) is None
    assert executor.handle(_incident("db-primary", 1, description="metric spike")) is None
    result = executor.handle(_incident("db-primary", 2, description="new log pattern: ERROR"))
    assert result is not None
    assert result.action == "restart_service"


def test_default_registry_has_all_referenced_actions():
    registry = default_registry()
    for name in ("restart_service", "scale_deployment", "clear_cache", "notify_only"):
        outcome = registry.get(name)({"service": "svc"})
        assert isinstance(outcome, ActionOutcome)
        assert "svc" in outcome.message
