# PostgreSQL Master-Slave Failover & Recovery

Scripted version of a two-node PostgreSQL 16 failover runbook: a streaming standby is promoted when the primary goes down, and the old primary is safely rejoined afterward as a standby of the new one — using `pg_rewind` instead of a full re-sync, without risking split-brain.

```
NODE_A (primary)  ── streaming replication ──▶  NODE_B (standby)
     port 5432                                       port 5432
```

## What's here

| Path | Purpose |
|---|---|
| `scripts/00-install-postgresql.sh` | Installs PostgreSQL 16 from the PGDG apt repo. Run on both nodes. |
| `scripts/01-setup-primary.sh` | Configures replication settings, creates the `replicator` role and app database, opens `pg_hba.conf` to the standby. Run on the primary. |
| `scripts/02-setup-standby.sh` | Wipes the data directory and takes a `pg_basebackup` from the primary (`-R` writes `standby.signal` + `primary_conninfo`). Run on the standby. **Destructive — requires `--yes`.** |
| `scripts/03-verify-replication.sh` | Reports whether the local node is primary or standby, and replication lag/state. Run on either node. |
| `scripts/04-promote-standby.sh` | Calls `pg_promote()` to make the standby writable. Run on the standby during a failover. |
| `scripts/05-grant-rewind-permissions.sh` | Grants the `replicator` role exactly the functions `pg_rewind` needs (not superuser). Run on the new primary. |
| `scripts/06-rejoin-as-standby.sh` | Cleanly stops the old primary, runs `pg_rewind` against the new primary, and restarts it as a standby. Run on the old primary. |
| `orchestrate/failover-drill.sh` | Runs the entire drill end-to-end over SSH from a control machine — kill, promote, rewind, rejoin, verify — for repeatable game-day testing. |
| `config.env.example` | Node IPs, paths, and credentials the scripts read from `config.env`. |

## Setup

```bash
cp config.env.example config.env   # fill in NODE_A_HOST, NODE_B_HOST, REPLICATOR_PASSWORD, etc.

# On NODE_A and NODE_B:
./scripts/00-install-postgresql.sh

# On NODE_A (primary):
STANDBY_HOST=<node_b_ip> REPLICATOR_PASSWORD=<pw> ./scripts/01-setup-primary.sh

# On NODE_B (standby):
PRIMARY_HOST=<node_a_ip> REPLICATOR_PASSWORD=<pw> ./scripts/02-setup-standby.sh --yes

# Either node:
./scripts/03-verify-replication.sh
```

## Running a failover drill

From a machine with SSH key access to both nodes:

```bash
cd orchestrate
./failover-drill.sh --yes
```

This deploys the scripts to both hosts, writes a canary row, kills PostgreSQL on `NODE_A`, promotes `NODE_B`, writes a second canary row on the new primary, grants `pg_rewind` permissions, rewinds and rejoins `NODE_A` as a standby of `NODE_B`, and verifies both canary rows are present on `NODE_A` afterward.

To fail back manually instead of via the drill script, run `05-grant-rewind-permissions.sh` on whichever node is currently primary and `06-rejoin-as-standby.sh` on whichever node needs to rejoin, pointing `NEW_PRIMARY_HOST` at the current primary.

## Why `pg_rewind` instead of a fresh `pg_basebackup`

After a failover, the old primary's data directory has diverged from the new primary (it kept accepting local WAL for whatever wasn't yet replicated at crash time). `pg_rewind` finds the last common checkpoint and copies over only the changed data pages, instead of re-copying the entire cluster — which matters when `PGDATA` is large. It requires the target to have been **cleanly shut down** (hence the start/sleep/stop cycle in `06-rejoin-as-standby.sh`) and either `wal_log_hints = on` or data checksums enabled on the source.

## Requirements

Two Ubuntu 22.04 hosts reachable on TCP 5432 and SSH · same PostgreSQL major version on both · `wal_log_hints = on` (set by `01-setup-primary.sh`) · SSH key access from the control machine for `orchestrate/failover-drill.sh`.

## Production hardening

- Automate with **repmgr** or **Patroni** instead of manual/scripted SSH runbooks for real incident response time — this repo is a reference implementation of the mechanics, not a substitute for a cluster manager.
- Use WAL archiving (pgBackRest/WAL-G) or generous `wal_keep_size` so WAL isn't recycled before a delayed rejoin can use it.
- Use `sslmode=verify-full` and real certificates — replication traffic between real hosts should never be plaintext.
- Restrict `pg_hba.conf` and firewall rules to exact peer IPs, never `0.0.0.0/0`.
- Monitor `pg_stat_replication` and lag; alert on WAL receiver disconnects.
- Run `orchestrate/failover-drill.sh` regularly against staging, not just once.
