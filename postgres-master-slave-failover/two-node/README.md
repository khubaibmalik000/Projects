# Two-Node Variant

Adaptation of the [Docker lab](../docker-lab/) for two real/virtual Ubuntu 22.04 hosts connected over a private network, using SSH and `systemctl` instead of `docker exec`. See the [top-level README](../README.md) for the shared rationale (why `pg_rewind`, the split-brain risk) — this page is setup/usage only.

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

## Requirements

Two Ubuntu 22.04 hosts reachable on TCP 5432 and SSH · same PostgreSQL major version on both · `wal_log_hints = on` (set by `01-setup-primary.sh`) · SSH key access from the control machine for `orchestrate/failover-drill.sh`.

## vs. the Docker lab

| Aspect | Docker lab | Two-node |
|---|---|---|
| Addressing | Container hostnames (`pg-master`, `pg-slave`) | Real IPs / DNS |
| `pg_hba.conf` source | `0.0.0.0/0` (lab only) | Specific peer IP/CIDR |
| Firewall | Not needed (isolated bridge network) | `ufw`/security groups must open 5432 between hosts |
| Start/stop/crash simulate | `docker start`/`stop`/`kill` | `systemctl start`/`stop`, `kill -9`, or power off the VM |
| Running `pg_rewind` | Throwaway container mounting the target's volume | Directly on the target node via SSH — no volume-mount trick needed |
| Access method | `docker exec` | SSH |
| TLS | Skipped in lab (plaintext `md5` over isolated bridge) | Use `sslmode=verify-full` and real certs — non-negotiable over a real network |
