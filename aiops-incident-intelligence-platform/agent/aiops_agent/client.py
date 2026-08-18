"""HTTP client for the AIOps ingestion API. Retries with linear backoff so
a brief network blip or API restart doesn't crash the agent loop.
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.request

logger = logging.getLogger("aiops_agent")


class ApiClient:
    def __init__(
        self,
        base_url: str,
        timeout: float = 5.0,
        max_retries: int = 3,
        backoff_seconds: float = 1.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.max_retries = max_retries
        self.backoff_seconds = backoff_seconds

    def post_metric(self, entity: str, metric: str, value: float) -> None:
        self._post("/v1/metrics", {"entity": entity, "metric": metric, "value": value})

    def post_log(self, entity: str, message: str) -> None:
        self._post("/v1/logs", {"entity": entity, "message": message})

    def post_topology(self, edges: list[tuple[str, str]]) -> None:
        self._post(
            "/v1/topology",
            {"edges": [{"upstream": u, "downstream": d} for u, d in edges]},
        )

    def _post(self, path: str, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        last_error: Exception | None = None
        for attempt in range(1, self.max_retries + 1):
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as response:
                    response.read()
                return
            except (urllib.error.URLError, TimeoutError) as exc:
                last_error = exc
                logger.warning(
                    "POST %s failed (attempt %d/%d): %s", path, attempt, self.max_retries, exc
                )
                if attempt < self.max_retries:
                    time.sleep(self.backoff_seconds * attempt)

        logger.error("giving up on POST %s after %d attempt(s): %s", path, self.max_retries, last_error)
