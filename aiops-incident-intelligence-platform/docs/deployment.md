# Deployment

Deploying the platform itself (below) gets you an empty API waiting for
data. To actually feed it real telemetry, run the [node agent](../agent/README.md)
on each server you want monitored.

## Local development

```bash
python -m venv .venv
source .venv/bin/activate   # .venv\Scripts\activate on Windows
pip install -e ".[dev]"

pytest                                 # run the test suite
python -m aiops.demo                   # run both synthetic scenarios end-to-end, no server needed
uvicorn aiops.api.main:app --reload    # start the API on http://localhost:8000
```

SQLite (`./aiops.db`) is the default store -- no external services
required for local dev or CI.

## Docker Compose (API + Postgres)

```bash
docker compose up --build
```

Brings up Postgres and the API (`AIOPS_DATABASE_URL` pointed at it
automatically). To also replay the cascading-failure scenario against the
running API and populate some incidents:

```bash
docker compose --profile demo run --rm load-generator
curl http://localhost:8000/v1/incidents | jq
```

## Kubernetes

Manifests in `deploy/k8s/`: a `Deployment` (2 replicas, resource
requests/limits, liveness/readiness probes on `/v1/health`), a
`ClusterIP` `Service`, and an `HorizontalPodAutoscaler` (CPU-based,
2-8 replicas). `secret.example.yaml` documents the expected
`AIOPS_DATABASE_URL` secret -- create the real one with `kubectl create
secret`, don't commit it.

```bash
kubectl create secret generic aiops-db-credentials \
  --from-literal=database-url='postgresql+psycopg2://aiops:CHANGE_ME@postgres:5432/aiops'
kubectl apply -f deploy/k8s/
```

Update the `image:` field in `deployment.yaml` to your registry before
applying -- it's a placeholder (`ghcr.io/OWNER/...`).

See [architecture.md](architecture.md#known-limitations) for the caveat
that runs multiple replicas with independent, non-shared detector state
-- appropriate for demoing horizontal scaling of the API/ingestion layer,
not for a strict "no duplicate incidents across replicas" guarantee.

## Configuration reference

All settings are environment variables read once at process start
(`aiops.config.Settings`).

| Variable | Default | Purpose |
|---|---|---|
| `AIOPS_DATABASE_URL` | `sqlite:///./aiops.db` | SQLAlchemy connection string |
| `AIOPS_EWMA_ALPHA` | `0.1` | EWMA smoothing factor for the statistical detector (lower = steadier variance estimate, fewer false positives; higher = faster drift adaptation) |
| `AIOPS_WARMUP_SAMPLES` | `20` | Samples before a series starts being scored |
| `AIOPS_WARN_SIGMA` | `3.0` | z-score threshold for `warning` |
| `AIOPS_CRIT_SIGMA` | `5.0` | z-score threshold for `critical` |
| `AIOPS_IFOREST_WINDOW` | `200` | Sliding window size per entity for the Isolation Forest |
| `AIOPS_IFOREST_MIN_SAMPLES` | `30` | Minimum buffered samples before the first fit |
| `AIOPS_IFOREST_RETRAIN_INTERVAL` | `50` | Observations between refits |
| `AIOPS_IFOREST_CONTAMINATION` | `0.05` | Expected outlier fraction passed to `IsolationForest` |
| `AIOPS_LOG_SIMILARITY_THRESHOLD` | `0.5` | Minimum token-match ratio to merge into an existing log template |
| `AIOPS_CORRELATION_WINDOW_SECONDS` | `120` | Max gap between an incident's last signal and a new one that still merges |
| `AIOPS_INCIDENT_CLOSE_AFTER_SECONDS` | `300` | Inactivity before an open incident auto-closes |
| `AIOPS_REMEDIATION_DRY_RUN` | `true` | Global default for whether remediation actions actually execute |
