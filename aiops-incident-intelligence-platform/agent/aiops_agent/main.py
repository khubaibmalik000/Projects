"""Entrypoint: collects system metrics (and optionally tails a log file) on
a fixed interval and forwards them to a running AIOps API instance.

Run with: python -m aiops_agent.main (or the aiops-node-agent console script).
All configuration is via environment variables -- see agent/README.md.
"""

from __future__ import annotations

import logging
import os
import signal
import time
from types import FrameType

from aiops_agent.client import ApiClient
from aiops_agent.collector import collect_system_metrics
from aiops_agent.log_tailer import LogTailer

logger = logging.getLogger("aiops_agent")

_running = True


def _handle_shutdown(signum: int, frame: FrameType | None) -> None:
    global _running
    logger.info("received signal %s, shutting down", signum)
    _running = False


def _parse_edges(raw: str) -> list[tuple[str, str]]:
    """Parses "upstream:downstream,upstream2:downstream2" into edge tuples."""
    edges = []
    for pair in raw.split(","):
        pair = pair.strip()
        if not pair:
            continue
        upstream, _, downstream = pair.partition(":")
        if upstream and downstream:
            edges.append((upstream.strip(), downstream.strip()))
    return edges


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("AIOPS_AGENT_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )

    api_base_url = os.environ.get("AIOPS_API_BASE_URL", "http://localhost:8000")
    entity = os.environ.get("AIOPS_AGENT_ENTITY")
    if not entity:
        raise SystemExit(
            "AIOPS_AGENT_ENTITY is required -- the service/node name this agent reports as"
        )
    interval = float(os.environ.get("AIOPS_AGENT_INTERVAL_SECONDS", "15"))
    log_file = os.environ.get("AIOPS_AGENT_LOG_FILE")
    edges = _parse_edges(os.environ.get("AIOPS_AGENT_TOPOLOGY_EDGES", ""))

    client = ApiClient(api_base_url)
    tailer = LogTailer(log_file) if log_file else None

    if edges:
        client.post_topology(edges)
        logger.info("registered %d topology edge(s)", len(edges))

    signal.signal(signal.SIGINT, _handle_shutdown)
    signal.signal(signal.SIGTERM, _handle_shutdown)

    logger.info(
        "aiops-node-agent starting: entity=%s api=%s interval=%ss log_file=%s",
        entity, api_base_url, interval, log_file or "(none)",
    )

    # cpu_percent(interval=None) reports 0.0 on its very first call -- it
    # needs a baseline measurement to compare the next call against.
    collect_system_metrics()

    while _running:
        try:
            for metric, value in collect_system_metrics().items():
                client.post_metric(entity, metric, value)
        except Exception:
            logger.exception("metric collection/send failed")

        if tailer is not None:
            try:
                for line in tailer.read_new_lines():
                    client.post_log(entity, line)
            except Exception:
                logger.exception("log tail/send failed")

        time.sleep(interval)


if __name__ == "__main__":
    main()
