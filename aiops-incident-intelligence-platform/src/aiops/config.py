"""Runtime configuration, sourced from environment variables with sane local defaults."""

from __future__ import annotations

import os
from dataclasses import dataclass


def _env_float(name: str, default: float) -> float:
    return float(os.environ.get(name, default))


def _env_int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    database_url: str = os.environ.get("AIOPS_DATABASE_URL", "sqlite:///./aiops.db")

    # Statistical (EWMA/z-score) anomaly detector
    ewma_alpha: float = _env_float("AIOPS_EWMA_ALPHA", 0.1)
    warmup_samples: int = _env_int("AIOPS_WARMUP_SAMPLES", 20)
    warn_sigma: float = _env_float("AIOPS_WARN_SIGMA", 3.0)
    crit_sigma: float = _env_float("AIOPS_CRIT_SIGMA", 5.0)

    # Isolation Forest multivariate detector
    iforest_window_size: int = _env_int("AIOPS_IFOREST_WINDOW", 200)
    iforest_min_samples: int = _env_int("AIOPS_IFOREST_MIN_SAMPLES", 30)
    iforest_retrain_interval: int = _env_int("AIOPS_IFOREST_RETRAIN_INTERVAL", 50)
    iforest_contamination: float = _env_float("AIOPS_IFOREST_CONTAMINATION", 0.05)

    # Log template mining
    log_similarity_threshold: float = _env_float("AIOPS_LOG_SIMILARITY_THRESHOLD", 0.5)

    # Correlation engine
    correlation_window_seconds: int = _env_int("AIOPS_CORRELATION_WINDOW_SECONDS", 120)
    incident_close_after_seconds: int = _env_int("AIOPS_INCIDENT_CLOSE_AFTER_SECONDS", 300)

    # Remediation
    remediation_dry_run: bool = _env_bool("AIOPS_REMEDIATION_DRY_RUN", True)


settings = Settings()
