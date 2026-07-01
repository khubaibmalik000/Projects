# k3d Observability Stack

A full self-hosted observability stack — metrics, logs, and dashboards — deployed to a local [k3d](https://k3d.io/) (k3s-in-Docker) cluster. Built as a sandbox to design and test Grafana dashboards against realistic, synthetic log/metric data before running the same manifests against a real cluster.

## Stack components

| File | Purpose |
|---|---|
| `k3d-cluster-config.yaml` | k3d cluster definition (2 servers, 5 agents) with host ports mapped for Prometheus (30090), Grafana (3000), and Loki (3100). |
| `prometheus.yaml` | Prometheus deployment, scrape config, and a `Secret` for authenticating to Node Exporter targets. |
| `grafana.yaml` | Grafana deployment with persistent storage, backed by a `PersistentVolume`/`PersistentVolumeClaim`. |
| `loki.yaml` | Loki deployment (log aggregation backend) with filesystem storage and a boltdb-shipper index. |
| `promtail.yaml` | Promtail DaemonSet that ships pod logs to Loki, with pipeline stages to parse pod/container labels and drop noisy containers. |
| `node-exporter-daemonset.yaml` | Node Exporter DaemonSet for host-level metrics, secured with basic auth. |
| `test-workload.yaml` | A synthetic multi-container pod (`dummy-apps`) that continuously emits structured `[INFO]`/`[ERROR]` log lines — used to validate that logs flow correctly through Promtail → Loki → Grafana, including error-pattern detection. |
| `dashboards/loki-logs-dashboard.json` | Custom Grafana dashboard for browsing/filtering the synthetic workload's logs via Loki. |

## Deployment order

```bash
# 1. Create the k3d cluster
k3d cluster create --config k3d-cluster-config.yaml

# 2. Deploy the stack
kubectl apply -f node-exporter-daemonset.yaml
kubectl apply -f prometheus.yaml
kubectl apply -f loki.yaml
kubectl apply -f promtail.yaml
kubectl apply -f grafana.yaml

# 3. Deploy the synthetic log-generating workload
kubectl apply -f test-workload.yaml
```

Then open Grafana at `http://localhost:3000`, add Prometheus (`http://prometheus.prometheus:9090`) and Loki (`http://loki.loki:3100`) as data sources, and import the dashboards from `dashboards/`.

## Credentials

Passwords in these manifests are placeholders (`CHANGE_ME_PASSWORD`) — set real values via `Secret`/env vars before deploying anywhere beyond a local sandbox.

## Requirements

- Docker
- [k3d](https://k3d.io/)
- `kubectl`
