# PostgreSQL Master-Slave Failover — VPS-Verified Edition

Gap-fixed, live-verified edition of the PostgreSQL 16 failover-and-rejoin runbook: a streaming standby is promoted when the primary goes down, and the old primary rejoins afterward as a standby via `pg_rewind`, without split-brain. Verified end-to-end on 2026-07-22 against two real Ubuntu 24.04 VPS hosts on public IPs — see [`VERIFICATION.md`](VERIFICATION.md) for the full pass/fail table and the five real Debian/Ubuntu packaging gaps found (and fixed here) that the [original Docker-lab-derived runbook](../postgres-master-slave-failover/) doesn't cover.

```
NODE_A (primary)  ── streaming replication ──▶  NODE_B (standby)
     port 5432                                       port 5432
```

## What's here

| Path | Purpose |
|---|---|
| `scripts/00-install-postgresql.sh` | Installs PostgreSQL 16 from the PGDG apt repo. Run on both nodes. |
| `scripts/01-setup-node.sh` | Configures replica-capable settings, the `replicator` role/app DB, and `pg_hba.conf` for the peer. **Run on both nodes**, symmetrically — fixes gap #1 (rejoin needs the new primary to already accept inbound connections). |
| `scripts/02-clone-as-standby.sh` | Wipes `PGDATA` and clones from the primary via `pg_basebackup -R`, always as the `postgres` user (gap #2). **Destructive — requires `--yes`.** |
| `scripts/03-verify-replication.sh` | Reports role and replication lag/state. Run on either node. |
| `scripts/04-simulate-outage.sh` | Takes the node down for a drill via `systemctl stop` (optionally preceded by `kill -9 --crash`) — `kill -9` alone doesn't work on a systemd-managed install (gap #5). |
| `scripts/05-promote-standby.sh` | Calls `pg_promote()`. |
| `scripts/06-grant-rewind-permissions.sh` | Grants `replicator` exactly the functions `pg_rewind` needs — not superuser. |
| `scripts/07-rejoin-as-standby.sh` | Cleanly stops, stages `/etc/postgresql/.../{postgresql.conf,pg_hba.conf,conf.d}` into `PGDATA` (gap #3), resolves the `pg_rewind` binary off `PATH` (gap #4), rewinds, cleans up the staged config, and restarts as a standby. |
| `orchestrate/failover-drill.sh` | The whole gap-fixed sequence over SSH from a control machine, for repeatable game-day drills. |
| `config.env.example` | Node IPs, paths, and credentials the scripts read from `config.env`. |
| `VERIFICATION.md` | The live verification report this project implements. |

## Setup

```bash
cp config.env.example config.env   # fill in NODE_A_HOST, NODE_B_HOST, REPLICATOR_PASSWORD, etc.

# On NODE_A and NODE_B:
./scripts/00-install-postgresql.sh

# On BOTH nodes — symmetric prep, not just the primary:
PEER_HOST=<other node's IP> REPLICATOR_PASSWORD=<pw> ./scripts/01-setup-node.sh

# On NODE_B (the one that will start as standby):
PRIMARY_HOST=<node_a_ip> REPLICATOR_PASSWORD=<pw> ./scripts/02-clone-as-standby.sh --yes

# Either node:
./scripts/03-verify-replication.sh
```

## Running a failover drill

```bash
cd orchestrate
./failover-drill.sh --yes
```

Deploys the scripts to both hosts, preps both symmetrically, clones the standby, writes a canary row, takes NODE_A down for real (not a `kill -9` that systemd just undoes), promotes NODE_B, writes a second canary row, grants `pg_rewind` permissions, rewinds and rejoins NODE_A as a standby of NODE_B — staging and cleaning up the `/etc` config Debian's `pg_rewind` needs along the way — and verifies both canary rows are present on NODE_A afterward.

## Requirements

Two Ubuntu 22.04+ hosts reachable on TCP 5432 and SSH (public IPs are fine — no shared LAN required) · same PostgreSQL major version on both · SSH key access from the control machine for `orchestrate/failover-drill.sh`.
