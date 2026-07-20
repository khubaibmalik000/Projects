#!/usr/bin/env bash
# Run locally (via sudo) on the standby node.
# DESTRUCTIVE: wipes PGDATA before taking the base backup. Requires --yes to run.
# Usage: PRIMARY_HOST=10.0.1.10 REPLICATOR_PASSWORD=... ./02-setup-standby.sh --yes
set -euo pipefail

: "${PRIMARY_HOST:?set PRIMARY_HOST to the primary node's IP}"
: "${REPLICATOR_PASSWORD:?set REPLICATOR_PASSWORD}"
PG_VERSION="${PG_VERSION:-16}"
REPLICATOR_USER="${REPLICATOR_USER:-replicator}"
PGDATA="${PGDATA:-/var/lib/postgresql/${PG_VERSION}/main}"

if [[ "${1:-}" != "--yes" ]]; then
  echo "This wipes ${PGDATA} on $(hostname). Re-run with --yes to confirm." >&2
  exit 1
fi

sudo systemctl stop postgresql
sudo rm -rf "${PGDATA:?}"/*

sudo -u postgres env PGPASSWORD="${REPLICATOR_PASSWORD}" pg_basebackup \
  -h "${PRIMARY_HOST}" -D "${PGDATA}" -U "${REPLICATOR_USER}" -v -P -R --wal-method=stream

sudo chmod 0700 "${PGDATA}"
sudo systemctl start postgresql
