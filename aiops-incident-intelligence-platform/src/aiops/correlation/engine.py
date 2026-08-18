"""Correlates raw anomaly signals into a small number of incidents.

This is the alert-fatigue-reduction piece: without correlation, a single
root failure (e.g. a database going slow) fans out into a metric anomaly,
a burst of new error log templates, and a downstream-service anomaly --
three-plus separate pages for one problem. The engine groups signals that
are close in time *and* related in the service dependency graph into one
incident, and ranks the most-upstream affected entity as the probable
root cause.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Literal

from aiops.correlation.dependency_graph import ServiceDependencyGraph

SignalKind = Literal["metric", "multivariate", "log"]

_SEVERITY_RANK = {"info": 0, "warning": 1, "error": 2, "critical": 3}


@dataclass
class Signal:
    entity: str
    kind: SignalKind
    description: str
    severity: str
    score: float
    timestamp: datetime
    source_id: str | None = None


@dataclass
class Incident:
    id: str
    signals: list[Signal] = field(default_factory=list)
    entities: set[str] = field(default_factory=set)
    opened_at: datetime = field(default_factory=lambda: datetime.min)
    last_seen_at: datetime = field(default_factory=lambda: datetime.min)
    probable_root_cause: str | None = None
    status: Literal["open", "closed"] = "open"

    @property
    def severity(self) -> str:
        worst = max(self.signals, key=lambda s: _SEVERITY_RANK.get(s.severity, 0))
        return worst.severity

    @property
    def signal_count(self) -> int:
        return len(self.signals)


class CorrelationEngine:
    def __init__(
        self,
        dependency_graph: ServiceDependencyGraph | None = None,
        correlation_window_seconds: int = 120,
        close_after_seconds: int = 300,
        related_max_hops: int = 2,
    ) -> None:
        self.graph = dependency_graph or ServiceDependencyGraph()
        self.window = timedelta(seconds=correlation_window_seconds)
        self.close_after = timedelta(seconds=close_after_seconds)
        self.related_max_hops = related_max_hops
        self._open: list[Incident] = []
        self._closed: list[Incident] = []
        self._counter = 0

    def ingest(self, signal: Signal) -> Incident:
        self._expire(signal.timestamp)

        incident = self._find_candidate(signal)
        if incident is None:
            self._counter += 1
            incident = Incident(
                id=f"INC-{self._counter:05d}",
                signals=[signal],
                entities={signal.entity},
                opened_at=signal.timestamp,
                last_seen_at=signal.timestamp,
                probable_root_cause=signal.entity,
            )
            self._open.append(incident)
            return incident

        incident.signals.append(signal)
        incident.entities.add(signal.entity)
        incident.last_seen_at = max(incident.last_seen_at, signal.timestamp)
        incident.probable_root_cause = self._rank_root_cause(incident)
        return incident

    def _find_candidate(self, signal: Signal) -> Incident | None:
        for incident in self._open:
            if signal.timestamp - incident.last_seen_at > self.window:
                continue
            if signal.entity in incident.entities:
                return incident
            if any(
                self.graph.related(signal.entity, entity, self.related_max_hops)
                for entity in incident.entities
            ):
                return incident
        return None

    def _rank_root_cause(self, incident: Incident) -> str:
        entities = incident.entities

        def upstream_score(entity: str) -> int:
            return sum(
                1
                for other in entities
                if other != entity and self.graph.is_upstream(entity, other)
            )

        earliest_by_entity = {
            entity: min(s.timestamp for s in incident.signals if s.entity == entity)
            for entity in entities
        }
        return max(
            entities,
            key=lambda e: (upstream_score(e), -earliest_by_entity[e].timestamp()),
        )

    def _expire(self, now: datetime) -> None:
        still_open = []
        for incident in self._open:
            if now - incident.last_seen_at > self.close_after:
                incident.status = "closed"
                self._closed.append(incident)
            else:
                still_open.append(incident)
        self._open = still_open

    def close_stale(self, now: datetime) -> list[Incident]:
        """Force-expire incidents relative to ``now`` (e.g. periodic sweep, not just on ingest)."""
        self._expire(now)
        return self.closed_incidents

    @property
    def open_incidents(self) -> list[Incident]:
        return list(self._open)

    @property
    def closed_incidents(self) -> list[Incident]:
        return list(self._closed)
