"""Multivariate anomaly detection via a periodically-retrained Isolation Forest.

Isolation Forest has no online/partial-fit mode, so each entity (service,
host, ...) keeps a bounded sliding-window buffer of recent feature vectors
and the model is refit against that window every ``retrain_interval``
observations. This trades a bit of staleness for detecting anomalies that
only show up across *combinations* of metrics (e.g. CPU and error rate both
mildly elevated together), which the univariate detector can't see.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from datetime import datetime

import numpy as np
from sklearn.ensemble import IsolationForest


@dataclass
class MultivariateAnomaly:
    entity: str
    score: float
    contributing_features: dict[str, float]
    timestamp: datetime


class IsolationForestDetector:
    def __init__(
        self,
        feature_names: list[str],
        window_size: int = 200,
        min_samples_to_fit: int = 30,
        retrain_interval: int = 50,
        contamination: float = 0.05,
        n_estimators: int = 100,
        random_state: int = 42,
    ) -> None:
        if min_samples_to_fit > window_size:
            raise ValueError("min_samples_to_fit cannot exceed window_size")
        self.feature_names = list(feature_names)
        self.window_size = window_size
        self.min_samples_to_fit = min_samples_to_fit
        self.retrain_interval = retrain_interval
        self.contamination = contamination
        self.n_estimators = n_estimators
        self.random_state = random_state

        self._buffers: dict[str, deque[list[float]]] = {}
        self._models: dict[str, IsolationForest] = {}
        self._since_retrain: dict[str, int] = {}

    def observe(
        self, entity: str, features: dict[str, float], timestamp: datetime
    ) -> MultivariateAnomaly | None:
        missing = [f for f in self.feature_names if f not in features]
        if missing:
            raise KeyError(f"observation missing required features: {missing}")

        buf = self._buffers.setdefault(entity, deque(maxlen=self.window_size))
        vector = [features[f] for f in self.feature_names]
        buf.append(vector)

        if len(buf) < self.min_samples_to_fit:
            return None

        since = self._since_retrain.get(entity, self.retrain_interval)
        model = self._models.get(entity)
        if model is None or since >= self.retrain_interval:
            model = IsolationForest(
                n_estimators=self.n_estimators,
                contamination=self.contamination,
                random_state=self.random_state,
            )
            model.fit(np.asarray(buf))
            self._models[entity] = model
            self._since_retrain[entity] = 0
        else:
            self._since_retrain[entity] = since + 1

        x = np.asarray(vector).reshape(1, -1)
        is_outlier = model.predict(x)[0] == -1
        if not is_outlier:
            return None

        score = float(-model.score_samples(x)[0])  # higher = more anomalous
        arr = np.asarray(buf)
        means = arr.mean(axis=0)
        stds = arr.std(axis=0)
        stds[stds == 0] = 1e-9
        deviations = np.abs((np.asarray(vector) - means) / stds)
        top = sorted(zip(self.feature_names, deviations.tolist()), key=lambda kv: -kv[1])[:3]

        return MultivariateAnomaly(
            entity=entity,
            score=score,
            contributing_features=dict(top),
            timestamp=timestamp,
        )

    def buffered_samples(self, entity: str) -> int:
        return len(self._buffers.get(entity, ()))
