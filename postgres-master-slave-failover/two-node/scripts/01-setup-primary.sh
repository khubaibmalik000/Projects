#!/usr/bin/env bash
# Run locally (via sudo) on the primary node.
# Usage: STANDBY_HOST=10.0.1.20 REPLICATOR_PASSWORD=... APP_DB=testdb ./01-setup-primary.sh
set -euo pipefail

: "${STANDBY_HOST:?set STANDBY_HOST to the standby node's IP/CIDR}"
: "${REPLICATOR_PASSWORD:?set REPLICATOR_PASSWORD}"
PG_VERSION="${PG_VERSION:-16}"
APP_DB="${APP_DB:-testdb}"
REPLICATOR_USER="${REPLICATOR_USER:-replicator}"
PG_CONF="${PG_CONF:-/etc/postgresql/${PG_VERSION}/main/postgresql.conf}"
PG_HBA="${PG_HBA:-/etc/postgresql/${PG_VERSION}/main/pg_hba.conf}"

# wal_log_hints is what lets pg_rewind work later without data checksums.
# wal_keep_size keeps enough WAL around that a delayed standby/rewind doesn't lose history.
if ! sudo grep -q '^wal_level = replica' "$PG_CONF"; then
  sudo tee -a "$PG_CONF" > /dev/null <<EOF
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
wal_log_hints = on
wal_keep_size = 512MB
EOF
else
  echo "postgresql.conf already has replica settings, skipping append"
fi

sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${REPLICATOR_USER}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE ROLE ${REPLICATOR_USER} WITH REPLICATION LOGIN PASSWORD '${REPLICATOR_PASSWORD}';"

sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${APP_DB}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE ${APP_DB};"

# Use the standby's real IP/CIDR — never 0.0.0.0/0 outside an isolated lab.
grep -q "replication ${REPLICATOR_USER} ${STANDBY_HOST}" "$PG_HBA" 2>/dev/null || \
  echo "host replication ${REPLICATOR_USER} ${STANDBY_HOST}/32 md5" | sudo tee -a "$PG_HBA" > /dev/null
grep -q "all all ${STANDBY_HOST}" "$PG_HBA" 2>/dev/null || \
  echo "host all all ${STANDBY_HOST}/32 md5" | sudo tee -a "$PG_HBA" > /dev/null

sudo systemctl restart postgresql
sudo systemctl status postgresql --no-pager
