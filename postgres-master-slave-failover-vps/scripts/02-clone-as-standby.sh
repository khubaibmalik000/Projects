#!/usr/bin/env bash
# Run locally (via sudo) on the node that will become the standby, after
# 01-setup-node.sh has already run on both nodes.
# DESTRUCTIVE: wipes PGDATA before taking the base backup. Requires --yes.
#
# Gap fix: pg_basebackup must run as the postgres OS user, not root — running
# it as root leaves the copied files root-owned and Postgres refuses to start
# until a manual `chown -R postgres:postgres` is done. `sudo -u postgres`
# below avoids that entirely.
#
# Usage: PRIMARY_HOST=<primary IP> REPLICATOR_PASSWORD=... ./02-clone-as-standby.sh --yes
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
