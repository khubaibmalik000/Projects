# Architecture

## Problem this solves

A single root-cause failure in a service-oriented system fans out into
many independent alerts: a metric crosses a threshold on the failing
service, error logs spike there and on every downstream caller, and
downstream metrics degrade a few seconds later as the failure propagates.
Without correlation, that's five-plus pages for one incident, and the
on-call engineer has to manually reconstruct which alert was the cause and
which were symptoms -- under time pressure, during the incident.

This platform ingests raw metric and log telemetry, detects anomalies in
each independently, and then correlates related anomalies (by time
proximity and service dependency) into a single incident with a ranked
probable root cause -- before a human ever looks at it.

## Data flow

```
metric points ──┬─▶ EwmaZScoreDetector ─────────┐
                └─▶ IsolationForestDetector ─────┤
                                                   ├─▶ CorrelationEngine ─▶ Incident ─▶ RemediationExecutor
log lines ──────────▶ LogTemplateMiner ──────────┘                                          │
                                                                                              ▼
                                                                                   RemediationResult (dry-run
                                                                                   by default) + persisted to DB
```

1. **Statistical anomaly detection** (`aiops.anomaly.statistical`) -- a
   per-series EWMA baseline with z-score scoring, catching single-metric
   threshold-style anomalies (latency spike, error-rate spike, ...).
2. **Multivariate anomaly detection** (`aiops.anomaly.ml`) -- a
   periodically-retrained Isolation Forest over a feature vector per
   entity, catching anomalies that only show up as a combination of
   metrics that individually look fine (see
   [algorithms.md](algorithms.md#isolation-forest-detector)).
3. **Log template mining** (`aiops.logs.drain`) -- a Drain-inspired
   streaming clustering algorithm that collapses the log stream into a
   small set of templates, so the platform can alert on *new* or *rare*
   templates instead of raw log volume.
4. **Correlation** (`aiops.correlation.engine`) -- groups anomaly signals
   that occur within a sliding time window *and* are connected in the
   service dependency graph into one `Incident`, and ranks the
   most-upstream affected entity as the probable root cause.
5. **Remediation** (`aiops.remediation`) -- a declarative rule book maps
   incident signatures (severity, entity prefix, description keywords) to
   a registered action (`restart_service`, `scale_deployment`,
   `clear_cache`, `notify_only`), with per-rule cooldowns to prevent
   remediation storms. Defaults to dry-run.
6. **Persistence** (`aiops.models`, `aiops.repository`) -- incidents,
   their signals, and remediation actions are persisted via SQLAlchemy
   (SQLite for local dev, Postgres in `docker-compose.yml` / Kubernetes).
7. **API** (`aiops.api`) -- FastAPI service exposing ingestion endpoints
   (`POST /v1/metrics`, `POST /v1/logs`), topology configuration
   (`POST /v1/topology`), and incident read endpoints
   (`GET /v1/incidents`, `GET /v1/incidents/{id}`). See
   [api.md](api.md).

All of the above is wired together in `aiops.pipeline.AiopsPipeline`,
which is the single object the API and the demo script both drive.

## Why these specific algorithms

- **EWMA + z-score over a full ML model for univariate anomalies**: cheap,
  interpretable (an on-call engineer can see "value X, baseline Y ± Z"),
  and adapts to drift without retraining. This is where most real
  metric anomalies live, so it shouldn't need a heavyweight model.
- **Isolation Forest for multivariate anomalies**: doesn't require
  labeled anomaly data (unsupervised), handles the "anomaly only visible
  across metrics" case the z-score detector structurally can't, and is
  cheap enough to refit every N observations on a bounded window.
- **Drain-style clustering for logs over full NLP/embedding approaches**:
  O(1)-ish per line (bucket lookup + token compare), fully streaming, and
  the output (a template + count) is directly actionable -- "this is a
  log line we've never seen before" is a strong, cheap signal.
- **Dependency-graph-based correlation over generic clustering**: alert
  correlation without domain context tends to either over-merge (any two
  alerts close in time become one incident) or under-merge (nothing
  correlates). Anchoring correlation to a real service topology makes
  root-cause ranking a graph question ("which affected entity is
  upstream of the others?") instead of a guess.

## Known limitations

- The correlation engine and detector state are in-process and
  single-instance; running the API with multiple replicas (as the
  Kubernetes manifests do) means each replica maintains independent
  anomaly baselines and open incidents. A production deployment would
  move detector/correlation state to a shared store (Redis, or a
  dedicated stream-processing tier) -- out of scope for this project but
  called out here deliberately rather than glossed over.
- Isolation Forest has no true online/partial-fit mode, so the
  multivariate detector trades some staleness (refit every
  `AIOPS_IFOREST_RETRAIN_INTERVAL` observations) for not needing a
  streaming ML framework.
- Remediation actions are dry-run by default and, even live, only run the
  registered Python callables in `aiops.remediation.executor` -- there is
  intentionally no free-form shell/command execution path.
