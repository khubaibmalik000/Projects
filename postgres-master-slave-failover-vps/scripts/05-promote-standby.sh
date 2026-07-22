#!/usr/bin/env bash
# Run locally on the standby node to promote it to primary during a failover.
set -euo pipefail

IN_RECOVERY=$(sudo -u postgres psql -tAc "SELECT pg_is_in_recovery();")
if [[ "$IN_RECOVERY" != "t" ]]; then
  echo "This node is already a primary (pg_is_in_recovery = f) — refusing to promote." >&2
  exit 1
fi

sudo -u postgres psql -c "SELECT pg_promote(wait := true);"
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
