#!/usr/bin/env bash
# Run locally on the OLD primary after a failover, to rejoin it as a standby
# of the newly promoted node. Do not just restart this node and leave it —
# it still thinks it's the primary and risks split-brain.
#
# Three Debian/Ubuntu-specific gaps this fixes, all hit during live VPS
# verification (the upstream runbook was written against a Docker image
# where none of these apply):
#
#   1. pg_rewind is not on PATH on Ubuntu — resolved via PG_REWIND_BIN,
#      falling back to /usr/lib/postgresql/$PG_VERSION/bin/pg_rewind.
#   2. pg_rewind launches Postgres in single-user mode against
#      --target-pgdata and expects postgresql.conf/pg_hba.conf/conf.d to
#      live INSIDE that directory. On Debian/Ubuntu they live in
#      /etc/postgresql/$PG_VERSION/main/ instead, so pg_rewind fails with
#      "postgres single-user mode in target cluster failed" unless they're
#      staged into PGDATA first — and cleaned up after, since pg_ctlcluster
#      (what Debian actually uses to start the cluster) reads config from
#      /etc, not PGDATA, and stale copies there would shadow real changes.
#   3. A postmaster left running from an earlier step (e.g. a stray
#      `systemctl start` while debugging the peer node) makes pg_rewind's
#      own start/stop cleanly-shut-down check meaningless — stop
#      unconditionally before proceeding, not just once.
#
# Usage: NEW_PRIMARY_HOST=<ip> REPLICATOR_PASSWORD=... ./07-rejoin-as-standby.sh
set -euo pipefail

: "${NEW_PRIMARY_HOST:?set NEW_PRIMARY_HOST to the newly promoted node's IP}"
: "${REPLICATOR_PASSWORD:?set REPLICATOR_PASSWORD}"
PG_VERSION="${PG_VERSION:-16}"
REPLICATOR_USER="${REPLICATOR_USER:-replicator}"
PGDATA="${PGDATA:-/var/lib/postgresql/${PG_VERSION}/main}"
PG_CONF_DIR="${PG_CONF_DIR:-/etc/postgresql/${PG_VERSION}/main}"
PG_REWIND_BIN="${PG_REWIND_BIN:-/usr/lib/postgresql/${PG_VERSION}/bin/pg_rewind}"
command -v pg_rewind >/dev/null 2>&1 && PG_REWIND_BIN=pg_rewind

# Let crash recovery finish (if this was a real crash), then shut down
# cleanly — pg_rewind requires a cleanly-shut-down target. Unconditional
# stop first guards against a postmaster left running from an earlier step.
sudo systemctl stop postgresql || true
sudo systemctl start postgresql
sleep 5
sudo journalctl -u postgresql -n 10 --no-pager
sudo systemctl stop postgresql
pg_lsclusters

echo ">>> Staging /etc config into PGDATA for pg_rewind's single-user-mode startup..."
sudo cp "${PG_CONF_DIR}/postgresql.conf" "${PGDATA}/"
sudo cp "${PG_CONF_DIR}/pg_hba.conf" "${PGDATA}/"
[ -d "${PG_CONF_DIR}/conf.d" ] && sudo cp -r "${PG_CONF_DIR}/conf.d" "${PGDATA}/"
sudo chown -R postgres:postgres "${PGDATA}/postgresql.conf" "${PGDATA}/pg_hba.conf"
[ -d "${PGDATA}/conf.d" ] && sudo chown -R postgres:postgres "${PGDATA}/conf.d"

sudo -u postgres "${PG_REWIND_BIN}" --target-pgdata="${PGDATA}" \
  --source-server="host=${NEW_PRIMARY_HOST} port=5432 user=${REPLICATOR_USER} password=${REPLICATOR_PASSWORD} dbname=postgres" \
  -R -P

echo ">>> Removing staged config from PGDATA (Debian starts the cluster from /etc via pg_ctlcluster)..."
sudo rm -f "${PGDATA}/postgresql.conf" "${PGDATA}/pg_hba.conf"
sudo rm -rf "${PGDATA}/conf.d"

sudo systemctl start postgresql
sudo journalctl -u postgresql -n 20 --no-pager

sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
