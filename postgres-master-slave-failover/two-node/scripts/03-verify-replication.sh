#!/usr/bin/env bash
# Run locally on either node. Reports role and replication health.
set -euo pipefail

IN_RECOVERY=$(sudo -u postgres psql -tAc "SELECT pg_is_in_recovery();")

if [[ "$IN_RECOVERY" == "f" ]]; then
  echo "Role: PRIMARY"
  echo
  sudo -u postgres psql -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"
else
  echo "Role: STANDBY (pg_is_in_recovery = t)"
  echo
  sudo -u postgres psql -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_delay;"
fi
