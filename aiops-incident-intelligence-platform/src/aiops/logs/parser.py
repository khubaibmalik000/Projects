"""Pre-processing helpers applied before a log line reaches the template miner."""

from __future__ import annotations

import re

_UUID_RE = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
)
_IPV4_RE = re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b")
_HEX_RE = re.compile(r"\b0x[0-9a-fA-F]+\b")
# No trailing \b: log numbers are routinely glued to a unit ("4321ms",
# "42s"), and \d immediately followed by a letter has no word boundary
# between them for \b to match on.
_NUMBER_RE = re.compile(r"(?<!\w)\d+(?:\.\d+)?")

_SEVERITY_KEYWORDS: tuple[tuple[str, tuple[str, ...]], ...] = (
    (
        "critical",
        ("panic", "fatal", "oom", "out of memory", "segfault", "deadlock", "corrupt"),
    ),
    (
        "error",
        ("error", "exception", "traceback", "failed", "failure", "refused", "timeout", "timed out"),
    ),
    ("warning", ("warn", "retry", "retrying", "deprecated", "slow")),
)


def mask_variables(message: str) -> str:
    """Replace high-cardinality tokens (IDs, IPs, numbers) with ``<*>``.

    Applied before tokenizing so the template miner clusters on log
    *structure* rather than treating every distinct value as a new pattern.
    """
    masked = _UUID_RE.sub("<*>", message)
    masked = _IPV4_RE.sub("<*>", masked)
    masked = _HEX_RE.sub("<*>", masked)
    masked = _NUMBER_RE.sub("<*>", masked)
    return masked


def classify_severity(message: str) -> str:
    """Best-effort severity from keyword matching. Falls back to ``info``."""
    lowered = message.lower()
    for severity, keywords in _SEVERITY_KEYWORDS:
        if any(kw in lowered for kw in keywords):
            return severity
    return "info"
