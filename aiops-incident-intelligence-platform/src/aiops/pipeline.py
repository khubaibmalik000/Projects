"""Wires the anomaly detectors, log miner, correlation engine, and remediation
executor into one streaming pipeline, and persists results after each event.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from aiops.anomaly.ml import IsolationForestDetector
from aiops.anomaly.statistical import EwmaZScoreDetector
from aiops.config import settings
from aiops.correlation.dependency_graph import ServiceDependencyGraph
from aiops.correlation.engine import CorrelationEngine, Incident, Signal
from aiops.db import SessionLocal, session_scope
from aiops.logs.drain import LogTemplateMiner
from aiops.remediation.executor import RemediationExecutor
from aiops.remediation.rules import RemediationRuleBook
from aiops.repository import record_remediation, upsert_incident

_LOG_SEVERITY_SCORE = {"warning": 2.0, "error": 3.0, "critical": 4.0}


@dataclass
class MetricPoint:
    entity: str
    metric: str
    value: float
    timestamp: datetime


@dataclass
class LogLine:
    entity: str
    message: str
    timestamp: datetime


class AiopsPipeline:
    def __init__(
        self,
        dependency_graph: ServiceDependencyGraph | None = None,
        multivariate_features: list[str] | None = None,
        remediation_rulebook: RemediationRuleBook | None = None,
        remediation_dry_run: bool | None = None,
        session_factory=None,
    ) -> None:
        self.statistical = EwmaZScoreDetector(
            alpha=settings.ewma_alpha,
            warmup_samples=settings.warmup_samples,
            warn_sigma=settings.warn_sigma,
            crit_sigma=settings.crit_sigma,
        )
        self.log_miner = LogTemplateMiner(
            similarity_threshold=settings.log_similarity_threshold
        )
        self.correlation = CorrelationEngine(
            dependency_graph=dependency_graph,
            correlation_window_seconds=settings.correlation_window_seconds,
            close_after_seconds=settings.incident_close_after_seconds,
        )
        self.remediation = RemediationExecutor(
            remediation_rulebook or RemediationRuleBook([]),
            dry_run=(
                settings.remediation_dry_run
                if remediation_dry_run is None
                else remediation_dry_run
            ),
        )
        self.session_factory = session_factory or SessionLocal

        self._iforest_feature_names = multivariate_features
        self._iforest = (
            IsolationForestDetector(
                feature_names=multivariate_features,
                window_size=settings.iforest_window_size,
                min_samples_to_fit=settings.iforest_min_samples,
                retrain_interval=settings.iforest_retrain_interval,
                contamination=settings.iforest_contamination,
            )
            if multivariate_features
            else None
        )
        self._metric_buffer: dict[str, dict[str, float]] = {}

    def ingest_metric(self, point: MetricPoint) -> list[Incident]:
        incidents: list[Incident] = []
        series_key = f"{point.entity}:{point.metric}"
        anomaly = self.statistical.observe(series_key, point.value, point.timestamp)
        if anomaly is not None:
            signal = Signal(
                entity=point.entity,
                kind="metric",
                description=(
                    f"{point.metric} = {point.value:.2f} "
                    f"(z={anomaly.z_score:.2f}, baseline {anomaly.baseline_mean:.2f}"
                    f"±{anomaly.baseline_std:.2f})"
                ),
                severity=anomaly.severity,
                score=abs(anomaly.z_score),
                timestamp=point.timestamp,
                source_id=series_key,
            )
            incidents.append(self._handle_signal(signal))

        if self._iforest is not None:
            buf = self._metric_buffer.setdefault(point.entity, {})
            buf[point.metric] = point.value
            if all(f in buf for f in self._iforest_feature_names):
                mv_anomaly = self._iforest.observe(point.entity, dict(buf), point.timestamp)
                if mv_anomaly is not None:
                    top_feature, top_dev = next(iter(mv_anomaly.contributing_features.items()))
                    signal = Signal(
                        entity=point.entity,
                        kind="multivariate",
                        description=(
                            f"multivariate outlier across {', '.join(self._iforest_feature_names)} "
                            f"(top factor: {top_feature}, {top_dev:.1f}σ from window mean)"
                        ),
                        severity="critical" if mv_anomaly.score > 0.6 else "warning",
                        score=mv_anomaly.score,
                        timestamp=point.timestamp,
                        source_id="iforest",
                    )
                    incidents.append(self._handle_signal(signal))
        return incidents

    def ingest_log(self, line: LogLine) -> Incident | None:
        event = self.log_miner.add_log_message(line.message, line.timestamp)
        is_notable = event.severity in {"error", "critical"} and (
            event.is_new_template or event.occurrence_count <= 3
        )
        if not is_notable:
            return None

        kind = "new" if event.is_new_template else "rare"
        signal = Signal(
            entity=line.entity,
            kind="log",
            description=f"{kind} log pattern: {event.template[:160]}",
            severity=event.severity,
            score=_LOG_SEVERITY_SCORE.get(event.severity, 1.0),
            timestamp=line.timestamp,
            source_id=f"template-{event.cluster_id}",
        )
        return self._handle_signal(signal)

    def _handle_signal(self, signal: Signal) -> Incident:
        incident = self.correlation.ingest(signal)
        remediation_result = self.remediation.handle(incident)
        with session_scope(self.session_factory) as session:
            upsert_incident(session, incident)
            if remediation_result is not None:
                record_remediation(session, remediation_result)
        return incident
