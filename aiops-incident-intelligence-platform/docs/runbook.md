# Runbook: extending the platform

## Adding a new remediation rule

Rules are declarative (`aiops.remediation.rules.RemediationRule`) and
matched in order; the first match wins. No code change is needed to add
a rule, only to add a new *action* if none of the existing ones fit.

```python
from aiops.remediation.rules import RemediationRule

RemediationRule(
    name="scale-orders-api-on-error-spike",
    action="scale_deployment",
    match_entity_prefix="orders-api",
    match_severity={"critical"},
    action_params={"replicas": "+2"},
    cooldown_seconds=600,
)
```

Add it to the `RemediationRuleBook` passed into `AiopsPipeline` (see
`aiops.api.deps` for where the API's default rule book is built).
`cooldown_seconds` is keyed per `(rule_name, probable_root_cause)`, so
one noisy entity can't re-trigger the same rule faster than the cooldown
even while other entities can.

## Adding a new remediation action

Actions are plain functions registered by name
(`dict -> ActionOutcome`), not shell strings -- there's no free-form
command execution to secure. Register a new one against
`aiops.remediation.executor.default_registry()` (or a custom
`ActionRegistry` passed into `RemediationExecutor`):

```python
from aiops.remediation.executor import ActionOutcome

def _rotate_credentials(params: dict) -> ActionOutcome:
    service = params.get("service", "unknown-service")
    return ActionOutcome(True, f"rotate credentials for '{service}'")

registry.register("rotate_credentials", _rotate_credentials)
```

Keep `dry_run=True` (the default) until the action is wired to a real
orchestrator and you've watched it fire correctly a few times in
dry-run mode.

## Adding a new anomaly signal source

Any detector that can produce a `(severity, description, score,
timestamp, entity)` tuple can feed the correlation engine -- it doesn't
care where a `Signal` came from. To wire in a new source:

1. Build the `Signal` (`aiops.correlation.engine.Signal`).
2. Call `pipeline.correlation.ingest(signal)`.
3. Optionally call `pipeline.remediation.handle(incident)` on the
   returned incident if this new source should be eligible for
   automated remediation.
4. Persist via `aiops.repository.upsert_incident` if the signal was
   produced outside of `AiopsPipeline`'s own `ingest_metric`/`ingest_log`
   entrypoints.

## Investigating a specific incident

```bash
curl http://localhost:8000/v1/incidents/INC-00007 | jq
```

`probable_root_cause` names the entity the correlation engine ranked as
most likely upstream; `signals` is the full evidence trail in arrival
order. If the root-cause call looks wrong, the first thing to check is
whether `POST /v1/topology` has been called with the correct edges for
the affected services -- an incorrect or incomplete dependency graph is
the most common cause of a bad ranking (see
[algorithms.md](algorithms.md#correlation-and-root-cause-ranking)).
