#!/usr/bin/env bash
# Run locally on the node playing "primary" for a drill.
#
# Gap fix: `kill -9 $(pgrep postgres)` alone does NOT simulate a real outage
# on a systemd-managed install — systemd's unit auto-restarts Postgres within
# seconds and the standby silently reconnects, so the drill never actually
# exercises promotion. This was observed directly: NODE_B's WAL receiver
# broke, then quietly resumed streaming before promotion could happen.
# `systemctl stop` is what actually takes the node down for the drill; use
# `--crash` first if you want to also exercise crash recovery on rejoin.
#
# Usage: ./04-simulate-outage.sh [--crash]
set -euo pipefail

PG_VERSION="${PG_VERSION:-16}"

if [[ "${1:-}" == "--crash" ]]; then
  sudo kill -9 "$(pgrep -f "postgres: ${PG_VERSION}/main")" || true
fi

sudo systemctl stop postgresql
pg_lsclusters
