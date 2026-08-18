"""Real system resource metrics, via psutil."""

from __future__ import annotations

import os

import psutil


def collect_system_metrics() -> dict[str, float]:
    metrics = {
        "cpu_percent": psutil.cpu_percent(interval=None),
        "memory_percent": psutil.virtual_memory().percent,
        "disk_percent": psutil.disk_usage(_root_path()).percent,
    }
    load1 = _load_average_1min()
    if load1 is not None:
        metrics["load1"] = load1
    return metrics


def _root_path() -> str:
    return "C:\\" if os.name == "nt" else "/"


def _load_average_1min() -> float | None:
    # os.getloadavg() doesn't exist on Windows
    getloadavg = getattr(os, "getloadavg", None)
    if getloadavg is None:
        return None
    try:
        return getloadavg()[0]
    except OSError:
        return None
