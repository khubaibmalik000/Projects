"""Declarative mapping from incident signatures to remediation actions."""

from __future__ import annotations

from dataclasses import dataclass, field

from aiops.correlation.engine import Incident


@dataclass
class RemediationRule:
    name: str
    action: str
    match_entity_prefix: str | None = None
    match_severity: set[str] = field(default_factory=lambda: {"critical"})
    match_description_contains: str | None = None
    action_params: dict = field(default_factory=dict)
    cooldown_seconds: int = 600


class RemediationRuleBook:
    def __init__(self, rules: list[RemediationRule]) -> None:
        self.rules = rules

    def match(self, incident: Incident) -> RemediationRule | None:
        for rule in self.rules:
            if self._matches(rule, incident):
                return rule
        return None

    @staticmethod
    def _matches(rule: RemediationRule, incident: Incident) -> bool:
        if rule.match_severity and incident.severity not in rule.match_severity:
            return False
        if rule.match_entity_prefix and not incident.probable_root_cause.startswith(
            rule.match_entity_prefix
        ):
            return False
        return not rule.match_description_contains or any(
            rule.match_description_contains.lower() in s.description.lower()
            for s in incident.signals
        )
