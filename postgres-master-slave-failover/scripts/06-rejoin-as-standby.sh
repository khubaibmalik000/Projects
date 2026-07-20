#!/usr/bin/env bash
# Run locally on the OLD primary after a failover, to rejoin it as a standby
# of the newly promoted node. Do not just restart this node and leave it —
# it still thinks it's the primary and risks split-brain.
#
# Usage: NEW_PRIMARY_HOST=10.0.1.20 REPLICATOR_PASSWORD=... ./06-rejoin-as-standby.sh
set -euo pipefail

: "${NEW_PRIMARY_HOST:?set NEW_PRIMARY_HOST to the newly promoted node's IP}"
: "${REPLICATOR_PASSWORD:?set REPLICATOR_PASSWORD}"
PG_VERSION="${PG_VERSION:-16}"
REPLICATOR_USER="${REPLICATOR_USER:-replicator}"
PGDATA="${PGDATA:-/var/lib/postgresql/${PG_VERSION}/main}"

# Let crash recovery finish, then shut down cleanly — pg_rewind requires a
# cleanly stopped target.
sudo systemctl start postgresql
sleep 5
sudo journalctl -u postgresql -n 10 --no-pager
sudo systemctl stop postgresql

sudo -u postgres pg_rewind --target-pgdata="${PGDATA}" \
  --source-server="host=${NEW_PRIMARY_HOST} port=5432 user=${REPLICATOR_USER} password=${REPLICATOR_PASSWORD} dbname=postgres" \
  -R -P

sudo systemctl start postgresql
sudo journalctl -u postgresql -n 20 --no-pager

sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
