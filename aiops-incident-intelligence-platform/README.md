# AIOps Incident Intelligence Platform

Streaming anomaly detection, log template mining, alert correlation, and
remediation for infrastructure telemetry — a small, real implementation
of the core AIOps loop: **detect → correlate → rank root cause →
remediate**, built to show the mechanism rather than wrap a vendor SDK
around it.

Given a stream of metric points and log lines, it:

1. flags statistical anomalies per metric series (EWMA + z-score) and
   multivariate anomalies per entity (periodically-retrained Isolation
   Forest),
2. clusters raw log lines into templates and flags new/rare
   `error`/`critical` patterns (Drain-inspired streaming algorithm),
3. correlates the resulting signals — by time window *and* service
   dependency graph — into a small number of incidents instead of one
   page per signal,
4. ranks the most-upstream affected service as the probable root cause,
5. matches the incident against a declarative remediation rule book and
   executes (dry-run by default) a registered action.

Everything above is plain, tested Python — no managed ML platform, no
vendor agent. See [docs/architecture.md](docs/architecture.md) for why
these specific algorithms, and [docs/algorithms.md](docs/algorithms.md)
for how each one actually works.

## Why

Alert fatigue is a well-known failure mode: a single root cause fans out
into a metric alert, a burst of new log error templates, and a
downstream-service alert — three-plus independent pages for one problem.
This platform exists to demonstrate the specific, checkable mechanisms
that reduce that: bounding what counts as "the same incident" with a real
dependency graph, ranking root cause instead of guessing, and gating
automated remediation behind rules with cooldowns instead of firing on
every signal.

## Quickstart

```bash
python -m venv .venv && source .venv/bin/activate   # .venv\Scripts\activate on Windows
pip install -e ".[dev]"

pytest                                 # 60+ tests across every module
python -m aiops.demo                   # run both synthetic scenarios end-to-end, no server needed
uvicorn aiops.api.main:app --reload    # start the API on http://localhost:8000
```

Or with Docker:

```bash
docker compose up --build
docker compose --profile demo run --rm load-generator   # replay a scenario against the running API
curl http://localhost:8000/v1/incidents | jq
```

## What `python -m aiops.demo` actually shows

Two synthetic scenarios, replayed through the real pipeline with no
server needed:

- **Cascading failure**: `db-primary`'s query latency spikes, which ~6-12
  seconds later shows up as an error-rate spike in `orders-api` and
  elevated p95 latency in `checkout-web` — three services, multiple
  metric and log signals, correlated into one incident with
  `db-primary` (correctly) ranked as the root cause.
- **Multivariate-only anomaly**: a worker whose CPU and queue depth are
  normally *anti-correlated* starts showing both rising together. Each
  value alone stays inside its historical range the whole time — no
  z-score ever fires — but the joint pattern is what the Isolation Forest
  catches. Demonstrates why the platform has two detector types, not one.

## Repository layout

```
src/aiops/
  anomaly/        statistical (EWMA/z-score) + multivariate (Isolation Forest) detectors
  logs/           Drain-inspired log template miner + preprocessing
  correlation/    service dependency graph + incident correlation/root-cause engine
  remediation/    declarative rule book + pluggable action registry + dry-run executor
  generators/     synthetic metric/log generators and two canned demo scenarios
  api/            FastAPI app: routes, request/response schemas, dependencies
  pipeline.py     wires all of the above into one streaming pipeline
  models.py       SQLAlchemy ORM (incidents, signals, remediations)
  repository.py   persistence layer between the in-memory engine and the DB
  demo.py         end-to-end scenario runner (python -m aiops.demo)
tests/            unit + integration tests (pytest)
docs/             architecture, algorithms, API reference, deployment, runbook
deploy/k8s/       Deployment, Service, HPA, secret template
scripts/          demo.py entrypoint, HTTP-based scenario replay for a running deployment
```

## Documentation

- [docs/architecture.md](docs/architecture.md) — data flow, module map, why these algorithms, known limitations
- [docs/algorithms.md](docs/algorithms.md) — the four non-trivial algorithms, in detail
- [docs/api.md](docs/api.md) — full HTTP API reference
- [docs/deployment.md](docs/deployment.md) — local dev, Docker Compose, Kubernetes, full config reference
- [docs/runbook.md](docs/runbook.md) — how to add a remediation rule, action, or signal source

The [GitHub Wiki](../../wiki) mirrors this documentation for browsing
without cloning.

## Testing

```bash
pytest -v
```

Covers: the EWMA detector's warmup/damping/threshold behavior, the
Isolation Forest detector against the anti-correlation scenario above,
the log template miner's masking/clustering/rarity logic, the dependency
graph's BFS relations, the correlation engine's grouping/root-cause/expiry
logic, the remediation executor's rule matching/cooldown/dry-run
behavior, the full pipeline end-to-end against the cascading-failure
scenario with DB persistence asserted, and the HTTP API via FastAPI's
`TestClient`.

CI (`.github/workflows/ci.yml`) runs the full suite on Python 3.11 and
3.12, lints with `ruff`, and builds the Docker image on every push.

## Configuration

Environment-variable driven; see the full table in
[docs/deployment.md](docs/deployment.md#configuration-reference). SQLite
by default, Postgres in `docker-compose.yml` and the Kubernetes
manifests.

## License

MIT
