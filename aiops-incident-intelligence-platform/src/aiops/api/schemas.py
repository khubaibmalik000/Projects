"""Request/response models for the HTTP API."""

from __future__ import annotations

from datetime import UTC, datetime

from pydantic import BaseModel, ConfigDict, Field


def _utcnow() -> datetime:
    return datetime.now(UTC)


class MetricIngestRequest(BaseModel):
    entity: str
    metric: str
    value: float
    timestamp: datetime = Field(default_factory=_utcnow)


class LogIngestRequest(BaseModel):
    entity: str
    message: str
    timestamp: datetime = Field(default_factory=_utcnow)


class TopologyEdge(BaseModel):
    upstream: str
    downstream: str


class TopologyRequest(BaseModel):
    edges: list[TopologyEdge]


class SignalOut(BaseModel):
    entity: str
    kind: str
    description: str
    severity: str
    score: float
    source_id: str | None
    timestamp: datetime

    model_config = ConfigDict(from_attributes=True)


class RemediationOut(BaseModel):
    rule_name: str
    action: str
    dry_run: bool
    success: bool
    message: str
    executed_at: datetime

    model_config = ConfigDict(from_attributes=True)


class IncidentOut(BaseModel):
    id: str
    status: str
    severity: str
    entities: list[str]
    probable_root_cause: str | None
    signal_count: int
    opened_at: datetime
    last_seen_at: datetime

    model_config = ConfigDict(from_attributes=True)


class IncidentDetailOut(IncidentOut):
    signals: list[SignalOut]
    remediations: list[RemediationOut]


class HealthOut(BaseModel):
    status: str
    version: str


def incident_out_from_domain(incident) -> IncidentOut:
    """Build an ``IncidentOut`` from the in-memory correlation-engine
    ``Incident`` dataclass (as opposed to the ORM record used by the
    read endpoints) -- its ``entities`` is a ``set``, which pydantic
    won't silently coerce into an ordered list.
    """
    return IncidentOut(
        id=incident.id,
        status=incident.status,
        severity=incident.severity,
        entities=sorted(incident.entities),
        probable_root_cause=incident.probable_root_cause,
        signal_count=incident.signal_count,
        opened_at=incident.opened_at,
        last_seen_at=incident.last_seen_at,
    )
