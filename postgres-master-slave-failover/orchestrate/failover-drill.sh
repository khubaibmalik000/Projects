#!/usr/bin/env bash
# Run from a control machine (your laptop, a bastion) with SSH key access to
# both nodes. Drives the full failover + rejoin runbook end-to-end so it can
# be run as a repeatable game-day drill, not just followed by hand over SSH.
#
# Usage: ./failover-drill.sh --yes
# Config: ../config.env (copy from config.env.example)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if [[ "${1:-}" != "--yes" ]]; then
  echo "This kills postgres on NODE_A and promotes NODE_B. Re-run with --yes to confirm." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ROOT/config.env"

SSH="ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@"
REMOTE_DIR="pg-failover-scripts"

log() { echo "[$(date +%H:%M:%S)] $*"; }

deploy_scripts() {
  local host=$1
  log "Deploying scripts to $host"
  ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${host}" "mkdir -p ${REMOTE_DIR}"
  scp -o StrictHostKeyChecking=accept-new -q "$ROOT"/scripts/*.sh "${SSH_USER}@${host}:${REMOTE_DIR}/"
}

run_on() {
  local host=$1; shift
  ${SSH}"${host}" "cd ${REMOTE_DIR} && $*"
}

deploy_scripts "$NODE_A_HOST"
deploy_scripts "$NODE_B_HOST"

log "Baseline: verifying replication is healthy"
run_on "$NODE_A_HOST" "bash 03-verify-replication.sh"
run_on "$NODE_B_HOST" "bash 03-verify-replication.sh"

log "Writing canary row on NODE_A (primary)"
run_on "$NODE_A_HOST" "sudo -u postgres psql -d ${APP_DB} -c \"CREATE TABLE IF NOT EXISTS demo(id serial primary key, note text); INSERT INTO demo(note) VALUES ('drill: before failover');\""

log "Simulating NODE_A crash (kill -9)"
run_on "$NODE_A_HOST" "sudo kill -9 \$(pgrep -f 'postgres: ${PG_VERSION}/main') || true"

log "Promoting NODE_B"
run_on "$NODE_B_HOST" "bash 04-promote-standby.sh"

log "Writing canary row on NODE_B (new primary)"
run_on "$NODE_B_HOST" "sudo -u postgres psql -d ${APP_DB} -c \"INSERT INTO demo(note) VALUES ('drill: written after failover');\""

log "Granting pg_rewind permissions on NODE_B"
REPLICATOR_USER="$REPLICATOR_USER" run_on "$NODE_B_HOST" "REPLICATOR_USER=${REPLICATOR_USER} bash 05-grant-rewind-permissions.sh"

log "Rejoining NODE_A as standby of NODE_B"
run_on "$NODE_A_HOST" "NEW_PRIMARY_HOST=${NODE_B_HOST} REPLICATOR_PASSWORD=${REPLICATOR_PASSWORD} REPLICATOR_USER=${REPLICATOR_USER} PG_VERSION=${PG_VERSION} PGDATA=${PGDATA} bash 06-rejoin-as-standby.sh"

log "Final verification"
run_on "$NODE_B_HOST" "bash 03-verify-replication.sh"
run_on "$NODE_A_HOST" "bash 03-verify-replication.sh"
run_on "$NODE_A_HOST" "sudo -u postgres psql -d ${APP_DB} -c 'SELECT * FROM demo;'"

log "Drill complete: NODE_B is primary, NODE_A rejoined as standby."
