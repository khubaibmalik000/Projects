"""FastAPI dependency providers: a per-request DB session and the process-wide pipeline."""

from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy.orm import Session

from aiops.correlation.dependency_graph import ServiceDependencyGraph
from aiops.db import SessionLocal
from aiops.pipeline import AiopsPipeline
from aiops.remediation.rules import RemediationRule, RemediationRuleBook

_default_rulebook = RemediationRuleBook(
    [
        RemediationRule(
            name="page-oncall-on-critical",
            action="notify_only",
            match_severity={"critical"},
            cooldown_seconds=300,
        ),
        RemediationRule(
            name="restart-on-repeated-error-logs",
            action="restart_service",
            match_severity={"critical", "error"},
            match_description_contains="log pattern",
            cooldown_seconds=900,
        ),
    ]
)

_pipeline = AiopsPipeline(
    dependency_graph=ServiceDependencyGraph(),
    remediation_rulebook=_default_rulebook,
)


def get_pipeline() -> AiopsPipeline:
    return _pipeline


def get_db() -> Iterator[Session]:
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()
