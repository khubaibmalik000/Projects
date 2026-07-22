# Docker Lab

Two-container PostgreSQL 16 failover lab on a private Docker network. This is the original, actually-tested version of the runbook — verified end-to-end on 2026-07-20: old master rejoined as standby, streamed from the new primary, and caught up on all data written during the outage. See the [two-node variant](../two-node/) for the same mechanics on real hosts, and the [top-level README](../README.md) for shared rationale.

| Container | Role | Port |
|---|---|---|
| `pg-master` | Primary (initially) | 5433 → 5432 |
| `pg-slave` | Standby (initially), later promoted to primary | 5434 → 5432 |

Replication user `replicator` (`REPLICATION LOGIN`), async streaming replication over the `pgnet` bridge network.

## What's here

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Defines `pg-master` and `pg-slave` on the `pgnet` bridge network. |
| `master-init/01-replication-setup.sh` | Runs via `docker-entrypoint-initdb.d` on first boot — creates the `replicator` role and opens `pg_hba.conf`. |
| `slave/Dockerfile`, `slave/slave-entrypoint.sh` | Custom entrypoint that runs `pg_basebackup` from `pg-master` before handing off to the normal Postgres entrypoint, since the slave's `PGDATA` must not be `initdb`'d locally. |
| `failover-drill.sh` | Builds and starts the lab, verifies baseline replication, kills `pg-master`, promotes `pg-slave`, rewinds and rejoins the old master, and verifies — the whole runbook as one command. |

## How to run this

```bash
docker compose build
docker compose up -d
docker compose logs -f pg-slave   # watch it take the base backup and start streaming
```

Verify replication is healthy:

```bash
docker exec -it pg-master psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
docker exec -it pg-slave psql -U postgres -c "SELECT pg_is_in_recovery();"
```

## Running the failover + rejoin drill

```bash
./failover-drill.sh --yes
```

This tears down and rebuilds the lab, writes a canary row, `docker kill`s `pg-master`, promotes `pg-slave` with `pg_promote()`, writes a second canary row on the new primary, grants `pg_rewind` the permissions it needs on `replicator` (least-privilege — not superuser), runs `pg_rewind` from a throwaway container mounting `pg-master`'s volume (no shared filesystem needed), and restarts `pg-master` so it rejoins as a standby. It finishes by confirming both canary rows are present on the rejoined `pg-master`.

To do it by hand instead, follow section 5–6 of the runbook this lab implements: `docker kill pg-master` → `pg_promote()` on `pg-slave` → `docker start pg-master; sleep 5; docker stop pg-master` (clean shutdown, required by `pg_rewind`) → grant the `pg_rewind` permissions on `pg-slave` → run `pg_rewind --source-server=... -R` from a throwaway `postgres:16` container mounting `pg-master`'s data volume → `docker start pg-master`.

## Gotcha hit during testing

Without the `pg_rewind` permission grant, rewind fails with `permission denied for function pg_read_binary_file` — a plain `REPLICATION LOGIN` role isn't enough, since `pg_rewind` needs to call low-level file-reading functions on the source. `failover-drill.sh` grants exactly the five functions needed rather than making `replicator` a superuser.

## Requirements

Docker + Docker Compose v2 (`docker compose`, not `docker-compose`) · no port conflicts on 5433/5434 · stop unrelated containers on the host first if resource-constrained.

## Reset / cleanup

```bash
docker compose down -v   # removes containers AND volumes — full reset
```

`pg_hba.conf` here uses `0.0.0.0/0` and plaintext `md5` deliberately — this is lab-only, isolated to the Docker bridge network. Never do this on a real network; see the [two-node variant](../two-node/) for the locked-down version.
