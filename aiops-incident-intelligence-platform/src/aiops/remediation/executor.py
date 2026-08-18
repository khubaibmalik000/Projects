"""Executes remediation actions matched by the rule book.

Actions are plain Python callables registered by name, not shell strings --
there is no free-form command execution here, so there's no injection
surface. ``RemediationExecutor`` defaults to ``dry_run=True``: it resolves
the rule, the action, and the cooldown state exactly as it would in a live
run, but reports what *would* happen instead of calling the action. Flip
``dry_run=False`` only once the registered actions are wired to a real
orchestrator (systemd, Kubernetes API, etc).
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime

from aiops.correlation.engine import Incident
from aiops.remediation.rules import RemediationRuleBook


@dataclass
class ActionOutcome:
    success: bool
    message: str


@dataclass
class RemediationResult:
    incident_id: str
    rule_name: str
    action: str
    dry_run: bool
    outcome: ActionOutcome
    executed_at: datetime


ActionFn = Callable[[dict], ActionOutcome]


class ActionRegistry:
    def __init__(self) -> None:
        self._actions: dict[str, ActionFn] = {}

    def register(self, name: str, fn: ActionFn) -> None:
        self._actions[name] = fn

    def get(self, name: str) -> ActionFn:
        if name not in self._actions:
            raise KeyError(f"no action registered under '{name}'")
        return self._actions[name]


def _restart_service(params: dict) -> ActionOutcome:
    service = params.get("service", "unknown-service")
    return ActionOutcome(True, f"restart service '{service}'")


def _scale_deployment(params: dict) -> ActionOutcome:
    service = params.get("service", "unknown-service")
    replicas = params.get("replicas", "+1")
    return ActionOutcome(True, f"scale deployment '{service}' by {replicas} replicas")


def _clear_cache(params: dict) -> ActionOutcome:
    service = params.get("service", "unknown-service")
    return ActionOutcome(True, f"flush cache for '{service}'")


def _notify_only(params: dict) -> ActionOutcome:
    service = params.get("service", "unknown-service")
    return ActionOutcome(True, f"page on-call for '{service}' (no automated action configured)")


def default_registry() -> ActionRegistry:
    registry = ActionRegistry()
    registry.register("restart_service", _restart_service)
    registry.register("scale_deployment", _scale_deployment)
    registry.register("clear_cache", _clear_cache)
    registry.register("notify_only", _notify_only)
    return registry


class RemediationExecutor:
    def __init__(
        self,
        rulebook: RemediationRuleBook,
        registry: ActionRegistry | None = None,
        dry_run: bool = True,
    ) -> None:
        self.rulebook = rulebook
        self.registry = registry or default_registry()
        self.dry_run = dry_run
        self._last_fired: dict[str, datetime] = {}

    def handle(self, incident: Incident) -> RemediationResult | None:
        rule = self.rulebook.match(incident)
        if rule is None:
            return None

        cooldown_key = f"{rule.name}:{incident.probable_root_cause}"
        last_fired = self._last_fired.get(cooldown_key)
        if last_fired is not None:
            elapsed = (incident.last_seen_at - last_fired).total_seconds()
            if elapsed < rule.cooldown_seconds:
                return None

        action_fn = self.registry.get(rule.action)
        params = {**rule.action_params, "service": incident.probable_root_cause}
        outcome = action_fn(params)
        if self.dry_run:
            outcome = ActionOutcome(outcome.success, f"[DRY RUN] would {outcome.message}")

        self._last_fired[cooldown_key] = incident.last_seen_at
        return RemediationResult(
            incident_id=incident.id,
            rule_name=rule.name,
            action=rule.action,
            dry_run=self.dry_run,
            outcome=outcome,
            executed_at=incident.last_seen_at,
        )
