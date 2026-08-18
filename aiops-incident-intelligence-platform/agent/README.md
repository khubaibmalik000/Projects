# AIOps Node Agent

The piece that connects a real server to the platform. The API only
accepts data that's pushed to it — this is what does the pushing: it
runs on a node, collects real system metrics every N seconds, optionally
tails a log file, and forwards both to a running AIOps API instance.

Deliberately a separate, lightweight package from the main platform: it
only depends on `psutil` and the standard library, so it can be deployed
to a plain node that has no business running FastAPI/SQLAlchemy/scikit-learn.

## What it collects

- `cpu_percent`, `memory_percent`, `disk_percent` (always)
- `load1` (1-minute load average, Linux/macOS only — skipped on Windows)
- any new lines appended to `AIOPS_AGENT_LOG_FILE`, if set

Each metric is sent as its own `entity:metric` series
(e.g. `orders-api-node-1:cpu_percent`), so the server's per-series
anomaly detector tracks them independently.

## Quickstart

```bash
cd agent
python -m venv .venv && source .venv/bin/activate   # .venv\Scripts\activate on Windows
pip install -e ".[dev]"

pytest   # unit tests: metric collection, log-tail offset tracking, HTTP retry/backoff

export AIOPS_API_BASE_URL=http://localhost:8000
export AIOPS_AGENT_ENTITY=my-server-1
aiops-node-agent
```

## Configuration

All via environment variables:

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `AIOPS_AGENT_ENTITY` | yes | — | The service/node name this agent reports as |
| `AIOPS_API_BASE_URL` | no | `http://localhost:8000` | Base URL of the running AIOps API |
| `AIOPS_AGENT_INTERVAL_SECONDS` | no | `15` | Seconds between collection cycles |
| `AIOPS_AGENT_LOG_FILE` | no | *(none)* | Path to a log file to tail and forward |
| `AIOPS_AGENT_TOPOLOGY_EDGES` | no | *(none)* | `upstream:downstream,upstream:downstream` — registered once on startup |
| `AIOPS_AGENT_LOG_LEVEL` | no | `INFO` | Agent's own log verbosity |

## Wiring up multiple nodes

Run one agent per node/service, each with its own `AIOPS_AGENT_ENTITY`.
To get correlation and root-cause ranking working across them, at least
one agent needs to register the dependency edges between those entity
names:

```bash
# on any one node -- edges are additive across agents
AIOPS_AGENT_TOPOLOGY_EDGES="db-primary:orders-api,orders-api:checkout-web"
```

This has to match the entity names the other agents are actually
reporting as, or the correlation engine won't know they're related — see
[../docs/algorithms.md](../docs/algorithms.md#correlation-and-root-cause-ranking).

## Running as a service

`systemd/aiops-node-agent.service` + `systemd/aiops-node-agent.env.example`
are a template for a real Linux deployment (auto-restart on failure,
`ProtectSystem=strict` sandboxing, runs as an unprivileged user):

```bash
sudo cp systemd/aiops-node-agent.env.example /etc/default/aiops-node-agent
sudo vi /etc/default/aiops-node-agent   # fill in real values
sudo cp systemd/aiops-node-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now aiops-node-agent
sudo journalctl -u aiops-node-agent -f
```

Adjust `ExecStart` in the unit file to wherever you actually install the
venv (the template assumes `/opt/aiops-node-agent/.venv`).

On Windows, run it via Task Scheduler (action: `aiops-node-agent.exe` from
the venv's `Scripts\` folder, trigger: at startup) or NSSM.

## Design notes

- **Retry with backoff, never crash the loop**: `ApiClient` retries a
  failed POST up to `max_retries` times with linear backoff, then logs
  and moves on. A single collection cycle failing (API restart, brief
  network blip) doesn't kill the agent process.
- **Log rotation-safe tailing**: `LogTailer` tracks a byte offset per
  file; if the file shrinks between reads (rotated or truncated), it
  restarts from the beginning instead of seeking past the end or erroring.
- **No shell-outs, no arbitrary file reads**: the only file this touches
  is the one path in `AIOPS_AGENT_LOG_FILE`, and metrics come from
  `psutil`'s structured API, not parsed command output.
