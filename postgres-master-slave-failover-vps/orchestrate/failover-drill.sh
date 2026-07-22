#!/usr/bin/env bash
# Run from a control machine with SSH key access to both nodes. Drives the
# gap-fixed runbook end-to-end: symmetric node prep on both hosts, clone,
# baseline verification, a real outage (not just kill -9), promotion,
# rewind-permission grant, rejoin, and final verification.
#
# Usage: ./failover-drill.sh --yes
# Config: ../config.env (copy from config.env.example)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if [[ "${1:-}" != "--yes" ]]; then
  echo "This wipes NODE_B's data directory and takes NODE_A down. Re-run with --yes to confirm." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ROOT/config.env"

REMOTE_DIR="pg-failover-vps-scripts"
log() { echo "[$(date +%H:%M:%S)] $*"; }

deploy_scripts() {
  local host=$1
  log "Deploying scripts to $host"
  ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${host}" "mkdir -p ${REMOTE_DIR}"
  scp -o StrictHostKeyChecking=accept-new -q "$ROOT"/scripts/*.sh "${SSH_USER}@${host}:${REMOTE_DIR}/"
}

run_on() {
  local host=$1; shift
  ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${host}" "cd ${REMOTE_DIR} && $*"
}

COMMON_ENV="PG_VERSION=${PG_VERSION} PGDATA=${PGDATA} PG_CONF=${PG_CONF} PG_HBA=${PG_HBA} PG_CONF_DIR=${PG_CONF_DIR} PG_REWIND_BIN=${PG_REWIND_BIN} REPLICATOR_USER=${REPLICATOR_USER} REPLICATOR_PASSWORD=${REPLICATOR_PASSWORD} APP_DB=${APP_DB}"

deploy_scripts "$NODE_A_HOST"
deploy_scripts "$NODE_B_HOST"

log "Symmetric prep: configuring both nodes to accept inbound from their peer"
run_on "$NODE_A_HOST" "${COMMON_ENV} PEER_HOST=${NODE_B_HOST} bash 01-setup-node.sh"
run_on "$NODE_B_HOST" "${COMMON_ENV} PEER_HOST=${NODE_A_HOST} bash 01-setup-node.sh"

log "Cloning NODE_B as a standby of NODE_A"
run_on "$NODE_B_HOST" "${COMMON_ENV} PRIMARY_HOST=${NODE_A_HOST} bash 02-clone-as-standby.sh --yes"

log "Baseline: verifying replication is healthy"
run_on "$NODE_A_HOST" "bash 03-verify-replication.sh"
run_on "$NODE_B_HOST" "bash 03-verify-replication.sh"

log "Writing canary row on NODE_A (primary)"
run_on "$NODE_A_HOST" "sudo -u postgres psql -d ${APP_DB} -c \"CREATE TABLE IF NOT EXISTS demo(id serial primary key, note text); INSERT INTO demo(note) VALUES ('drill: before failover');\""

log "Simulating a real outage on NODE_A (systemctl stop, not just kill -9)"
run_on "$NODE_A_HOST" "${COMMON_ENV} bash 04-simulate-outage.sh --crash"

log "Promoting NODE_B"
run_on "$NODE_B_HOST" "bash 05-promote-standby.sh"

log "Writing canary row on NODE_B (new primary)"
run_on "$NODE_B_HOST" "sudo -u postgres psql -d ${APP_DB} -c \"INSERT INTO demo(note) VALUES ('drill: written after failover');\""

log "Granting pg_rewind permissions on NODE_B"
run_on "$NODE_B_HOST" "REPLICATOR_USER=${REPLICATOR_USER} bash 06-grant-rewind-permissions.sh"

log "Rejoining NODE_A as standby of NODE_B"
run_on "$NODE_A_HOST" "${COMMON_ENV} NEW_PRIMARY_HOST=${NODE_B_HOST} bash 07-rejoin-as-standby.sh"

log "Final verification"
run_on "$NODE_B_HOST" "bash 03-verify-replication.sh"
run_on "$NODE_A_HOST" "bash 03-verify-replication.sh"
run_on "$NODE_A_HOST" "sudo -u postgres psql -d ${APP_DB} -c 'SELECT * FROM demo;'"

log "Drill complete: NODE_B is primary, NODE_A rejoined as standby."
