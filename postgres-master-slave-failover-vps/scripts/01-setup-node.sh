#!/usr/bin/env bash
# Run locally (via sudo) on BOTH nodes, before deciding which starts as primary.
#
# Gap fix: the original runbook only configured listen_addresses/pg_hba.conf
# on the primary. That's fine until the standby is promoted and the old
# primary needs to rejoin — at that point pg_rewind connects FROM the old
# primary TO the new one, and if the new primary (originally the standby)
# was never configured to accept inbound connections, rewind fails with
# "Connection refused". Running this on both nodes up front means either one
# is ready to be the pg_rewind source, regardless of which way roles flip.
#
# Usage: PEER_HOST=<other node's IP> REPLICATOR_PASSWORD=... ./01-setup-node.sh
set -euo pipefail

: "${PEER_HOST:?set PEER_HOST to the other node's IP}"
: "${REPLICATOR_PASSWORD:?set REPLICATOR_PASSWORD}"
PG_VERSION="${PG_VERSION:-16}"
APP_DB="${APP_DB:-testdb}"
REPLICATOR_USER="${REPLICATOR_USER:-replicator}"
PG_CONF="${PG_CONF:-/etc/postgresql/${PG_VERSION}/main/postgresql.conf}"
PG_HBA="${PG_HBA:-/etc/postgresql/${PG_VERSION}/main/pg_hba.conf}"

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
# listen_addresses may already be set to the packaged default (localhost) by
# a prior partial run — force it regardless of the block above.
sudo sed -i "s/^#\?listen_addresses = .*/listen_addresses = '*'/" "$PG_CONF"

sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${REPLICATOR_USER}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE ROLE ${REPLICATOR_USER} WITH REPLICATION LOGIN PASSWORD '${REPLICATOR_PASSWORD}';"

sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${APP_DB}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE ${APP_DB};"

# Peer's real IP/CIDR — never 0.0.0.0/0 outside an isolated lab.
grep -q "replication ${REPLICATOR_USER} ${PEER_HOST}" "$PG_HBA" 2>/dev/null || \
  echo "host replication ${REPLICATOR_USER} ${PEER_HOST}/32 md5" | sudo tee -a "$PG_HBA" > /dev/null
grep -q "all all ${PEER_HOST}" "$PG_HBA" 2>/dev/null || \
  echo "host all all ${PEER_HOST}/32 md5" | sudo tee -a "$PG_HBA" > /dev/null

sudo systemctl restart postgresql
sudo systemctl status postgresql --no-pager
sudo ss -tlnp 2>/dev/null | grep 5432 || true
