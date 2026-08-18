"""Streaming log template mining, inspired by the Drain fixed-depth parse-tree algorithm.

Log lines are masked (variables -> ``<*>``), bucketed by (token count, first
token) for O(1)-ish lookup, then matched against existing templates in that
bucket by positional token similarity. A match above threshold merges the
line into the template (diverging positions become wildcards); otherwise a
new template cluster is created. This turns an unbounded stream of raw log
lines into a small, stable set of templates plus a count per template --
the basis for both noise reduction (only alert on *new* or *rare* templates)
and log-volume anomaly detection.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from aiops.logs.parser import classify_severity, mask_variables

WILDCARD = "<*>"


@dataclass
class LogEvent:
    cluster_id: int
    template: str
    raw: str
    severity: str
    is_new_template: bool
    occurrence_count: int
    timestamp: datetime


@dataclass
class _Cluster:
    id: int
    template_tokens: list[str]
    count: int = 0


class LogTemplateMiner:
    def __init__(self, similarity_threshold: float = 0.5) -> None:
        if not 0 < similarity_threshold <= 1:
            raise ValueError("similarity_threshold must be in (0, 1]")
        self.similarity_threshold = similarity_threshold
        self._buckets: dict[tuple[int, str], list[_Cluster]] = {}
        self._next_id = 1

    def add_log_message(self, message: str, timestamp: datetime) -> LogEvent:
        masked = mask_variables(message)
        tokens = masked.split()
        bucket_key = (len(tokens), tokens[0] if tokens else "")
        bucket = self._buckets.setdefault(bucket_key, [])

        best_cluster: _Cluster | None = None
        best_similarity = 0.0
        for cluster in bucket:
            similarity = self._similarity(cluster.template_tokens, tokens)
            if similarity > best_similarity:
                best_similarity, best_cluster = similarity, cluster

        is_new_template = False
        if best_cluster is not None and best_similarity >= self.similarity_threshold:
            cluster = best_cluster
            cluster.template_tokens = self._merge(cluster.template_tokens, tokens)
            cluster.count += 1
        else:
            cluster = _Cluster(id=self._next_id, template_tokens=tokens, count=1)
            self._next_id += 1
            bucket.append(cluster)
            is_new_template = True

        return LogEvent(
            cluster_id=cluster.id,
            template=" ".join(cluster.template_tokens),
            raw=message,
            severity=classify_severity(message),
            is_new_template=is_new_template,
            occurrence_count=cluster.count,
            timestamp=timestamp,
        )

    @property
    def template_count(self) -> int:
        return sum(len(bucket) for bucket in self._buckets.values())

    @staticmethod
    def _similarity(template_tokens: list[str], tokens: list[str]) -> float:
        if len(template_tokens) != len(tokens):
            return 0.0
        if not tokens:
            return 1.0
        matches = sum(
            1 for t, m in zip(template_tokens, tokens) if t == m or t == WILDCARD
        )
        return matches / len(tokens)

    @staticmethod
    def _merge(template_tokens: list[str], tokens: list[str]) -> list[str]:
        return [t if t == m else WILDCARD for t, m in zip(template_tokens, tokens)]
