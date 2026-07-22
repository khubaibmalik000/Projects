# Live Verification Report

Verified **2026-07-22** against two independent VPS hosts on separate public IPs (Ubuntu 24.04.4 LTS, PostgreSQL 16.14/pgdg) — no shared private LAN, `ufw` inactive on both, access control enforced entirely via `pg_hba.conf` `/32` peer rules. IPs are omitted here; substitute `NODE_A_HOST` / `NODE_B_HOST` from `config.env`.

## Result

| Step | Result |
|---|---|
| Install PostgreSQL 16 on both nodes | PASS |
| Configure primary | PASS |
| Configure standby | PASS |
| Baseline replication (streaming, data flow — 101/101 rows) | PASS |
| Simulate outage, promote standby | PASS |
| Rejoin old primary via `pg_rewind` | PASS |

The underlying Postgres mechanics (`pg_promote`, `pg_rewind`, `standby.signal`, streaming replication) are sound and reproduce correctly on real nodes. Every gap below is a **packaging/environment** issue, not a mechanics issue — all were hit running the original Docker-oriented runbook against real Debian/Ubuntu package installs, and all are fixed in this project's scripts.

## Gaps found and fixed here

1. **Peer node must also accept inbound connections.** The original runbook only configures `listen_addresses`/`pg_hba.conf` on the primary. Once roles reverse, the same configuration is needed on the other node *before* the rejoin step, or `pg_rewind` fails with `Connection refused`. → `scripts/01-setup-node.sh` runs symmetrically on both nodes before either becomes primary.
2. **`pg_basebackup` must run as the `postgres` OS user, not root** — otherwise a manual `chown -R postgres:postgres` is required before the standby will start. → `scripts/02-clone-as-standby.sh` always runs it via `sudo -u postgres`.
3. **`pg_rewind` needs `postgresql.conf`/`pg_hba.conf`/`conf.d` inside `PGDATA`** on Debian/Ubuntu package installs, since these normally live in `/etc/postgresql/<version>/main/` instead. `pg_rewind` launches Postgres in single-user mode directly against `--target-pgdata` and fails with `postgres single-user mode in target cluster failed` if they're missing. → `scripts/07-rejoin-as-standby.sh` stages copies into `PGDATA` before rewinding and removes them afterward (`pg_ctlcluster`, what Debian actually uses to start the cluster, reads from `/etc`, not `PGDATA` — stale copies left behind would shadow real config changes).
4. **`pg_rewind` is not on `PATH` on Ubuntu.** → resolved via `PG_REWIND_BIN` (default `/usr/lib/postgresql/<version>/bin/pg_rewind`), falling back to `pg_rewind` if it happens to be on `PATH`.
5. **`kill -9` alone does not simulate a real outage on a systemd-managed install** — the unit auto-restarts within seconds and the standby silently reconnects, so a naive drill never actually exercises promotion. → `scripts/04-simulate-outage.sh` follows the kill with `systemctl stop`, which is what actually takes the node down for the drill.

A sixth, minor issue — a stray running postmaster left over from debugging the peer node, which made the "cleanly shut down" precondition for `pg_rewind` unreliable — is handled by making `07-rejoin-as-standby.sh` stop the service unconditionally before its start/stop cycle, rather than assuming a clean starting state.

## Relationship to the other project

[`postgres-master-slave-failover`](../postgres-master-slave-failover/) has the Docker lab this runbook was originally written against, plus an earlier, unverified two-node adaptation. This project supersedes that adaptation with the fixes above, verified live rather than reasoned about.
