"""Persists the in-memory correlation-engine state (dataclasses) to the ORM tables."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from aiops.correlation.engine import Incident
from aiops.models import IncidentRecord, RemediationRecord, SignalRecord
from aiops.remediation.executor import RemediationResult


def upsert_incident(session: Session, incident: Incident) -> None:
    record = session.get(IncidentRecord, incident.id)
    if record is None:
        record = IncidentRecord(id=incident.id, opened_at=incident.opened_at)
        session.add(record)

    record.status = incident.status
    record.severity = incident.severity
    record.entities = sorted(incident.entities)
    record.probable_root_cause = incident.probable_root_cause
    record.last_seen_at = incident.last_seen_at
    session.flush()

    # Signals accumulate on the in-memory Incident; only append the ones
    # not yet persisted rather than diffing the whole list each time.
    already_persisted = (
        session.query(SignalRecord).filter_by(incident_id=incident.id).count()
    )
    for signal in incident.signals[already_persisted:]:
        session.add(
            SignalRecord(
                incident_id=incident.id,
                entity=signal.entity,
                kind=signal.kind,
                description=signal.description,
                severity=signal.severity,
                score=signal.score,
                source_id=signal.source_id,
                timestamp=signal.timestamp,
            )
        )


def record_remediation(session: Session, result: RemediationResult) -> None:
    session.add(
        RemediationRecord(
            incident_id=result.incident_id,
            rule_name=result.rule_name,
            action=result.action,
            dry_run=result.dry_run,
            success=result.outcome.success,
            message=result.outcome.message,
            executed_at=result.executed_at,
        )
    )


def list_incidents(
    session: Session, status: str | None = None, limit: int = 100
) -> list[IncidentRecord]:
    stmt = select(IncidentRecord).order_by(IncidentRecord.last_seen_at.desc()).limit(limit)
    if status is not None:
        stmt = stmt.where(IncidentRecord.status == status)
    return list(session.scalars(stmt))


def get_incident(session: Session, incident_id: str) -> IncidentRecord | None:
    return session.get(IncidentRecord, incident_id)
