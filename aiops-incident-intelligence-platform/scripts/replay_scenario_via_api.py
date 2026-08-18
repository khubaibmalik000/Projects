#!/usr/bin/env python
"""Replays the cascading-failure scenario against a *running* API instance
over HTTP (as opposed to ``aiops.demo``, which drives the pipeline
in-process). Used by the docker-compose ``load-generator`` service, and
useful for manually exercising a deployed instance.

Usage: AIOPS_API_BASE_URL=http://localhost:8000 python scripts/replay_scenario_via_api.py
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from aiops.generators.scenario import cascading_failure_scenario  # noqa: E402

API_BASE_URL = os.environ.get("AIOPS_API_BASE_URL", "http://localhost:8000")


def _post(path: str, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{API_BASE_URL}{path}", data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        response.read()


def wait_for_api(timeout_seconds: int = 60) -> None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            urllib.request.urlopen(f"{API_BASE_URL}/v1/health", timeout=2)
            return
        except (urllib.error.URLError, ConnectionError):
            time.sleep(1)
    raise TimeoutError(f"API at {API_BASE_URL} did not become healthy in time")


def main() -> None:
    wait_for_api()

    scenario = cascading_failure_scenario(start=datetime.now(timezone.utc))
    _post(
        "/v1/topology",
        {
            "edges": [
                {"upstream": "db-primary", "downstream": "orders-api"},
                {"upstream": "orders-api", "downstream": "checkout-web"},
            ]
        },
    )

    for point in scenario.metric_points:
        _post(
            "/v1/metrics",
            {
                "entity": point.entity,
                "metric": point.metric,
                "value": point.value,
                "timestamp": point.timestamp.isoformat(),
            },
        )
    for line in scenario.log_lines:
        _post(
            "/v1/logs",
            {"entity": line.entity, "message": line.message, "timestamp": line.timestamp.isoformat()},
        )

    print(f"Replayed {len(scenario.metric_points)} metric points and "
          f"{len(scenario.log_lines)} log lines to {API_BASE_URL}. "
          f"Check GET {API_BASE_URL}/v1/incidents")


if __name__ == "__main__":
    main()
