# API Reference

Base path: `/v1`. Interactive Swagger UI is served at `/docs` (FastAPI
default) when the service is running.

## `GET /v1/health`

```json
{ "status": "ok", "version": "1.0.0" }
```

## `POST /v1/topology`

Registers service-dependency edges used by the correlation engine.
Additive -- repeated calls accumulate edges.

Request:

```json
{ "edges": [{ "upstream": "db-primary", "downstream": "orders-api" }] }
```

Response: `204 No Content`.

## `POST /v1/metrics`

Ingests one metric observation. Runs it through the statistical detector
(and the multivariate detector, if configured for this deployment).
Returns the list of incidents the resulting signal(s) were merged into
(usually 0 or 1; occasionally 2 if a point trips both detectors and they
land in different incidents).

Request:

```json
{
  "entity": "db-primary",
  "metric": "query_latency_ms",
  "value": 842.3,
  "timestamp": "2026-01-01T00:05:00Z"
}
```

`timestamp` is optional and defaults to now (UTC).

Response: `IncidentOut[]` (see below).

## `POST /v1/logs`

Ingests one log line. Runs it through the log template miner; only
new/rare `error`/`critical`-severity templates produce a signal.

Request:

```json
{ "entity": "db-primary", "message": "ERROR connection to db-primary refused after 4230ms, retrying" }
```

Response: `IncidentOut | null` -- `null` when the line wasn't notable
enough to become a signal.

## `GET /v1/incidents`

Query params: `status` (`open` | `closed`, optional), `limit` (default
100).

Response: `IncidentOut[]`, newest-first by `last_seen_at`.

```json
{
  "id": "INC-00001",
  "status": "open",
  "severity": "critical",
  "entities": ["db-primary", "orders-api"],
  "probable_root_cause": "db-primary",
  "signal_count": 4,
  "opened_at": "2026-01-01T00:05:00Z",
  "last_seen_at": "2026-01-01T00:06:10Z"
}
```

## `GET /v1/incidents/{id}`

`IncidentOut` plus the full signal and remediation history:

```json
{
  "...": "...IncidentOut fields...",
  "signals": [
    {
      "entity": "db-primary",
      "kind": "metric",
      "description": "query_latency_ms = 842.30 (z=6.11, baseline 20.40±2.10)",
      "severity": "critical",
      "score": 6.11,
      "source_id": "db-primary:query_latency_ms",
      "timestamp": "2026-01-01T00:05:00Z"
    }
  ],
  "remediations": [
    {
      "rule_name": "page-oncall-on-critical",
      "action": "notify_only",
      "dry_run": true,
      "success": true,
      "message": "[DRY RUN] would page on-call for 'db-primary' (no automated action configured)",
      "executed_at": "2026-01-01T00:05:00Z"
    }
  ]
}
```

404 with `{"detail": "incident '...' not found"}` if the ID doesn't exist.
