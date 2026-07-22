#!/usr/bin/env bash
# Runs the full lab end-to-end: build/start, verify baseline replication,
# kill pg-master, promote pg-slave, rejoin the old master via pg_rewind, and
# verify. Automates sections 4-6 of the runbook so the drill is repeatable
# instead of a sequence of commands to run by hand.
#
# Usage: ./failover-drill.sh --yes   (from this directory)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

if [[ "${1:-}" != "--yes" ]]; then
  echo "This tears down and rebuilds pg-master/pg-slave, then kills pg-master. Re-run with --yes to confirm." >&2
  exit 1
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }
psql_master() { docker exec -i pg-master psql -U postgres "$@"; }
psql_slave()  { docker exec -i pg-slave  psql -U postgres "$@"; }

log "Building and starting the lab"
docker compose down -v --remove-orphans >/dev/null 2>&1 || true
docker compose build
docker compose up -d

log "Waiting for pg-slave to enter streaming replication"
for _ in $(seq 1 30); do
  if psql_master -tAc "SELECT state FROM pg_stat_replication;" 2>/dev/null | grep -q streaming; then
    break
  fi
  sleep 2
done
psql_master -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
psql_slave -c "SELECT pg_is_in_recovery();"

log "Writing canary row on pg-master"
psql_master -d testdb -c "CREATE TABLE IF NOT EXISTS demo(id serial primary key, note text); INSERT INTO demo(note) VALUES ('before failover');"

log "Killing pg-master (simulated crash)"
docker kill pg-master
docker logs --tail 10 pg-slave

log "Promoting pg-slave"
psql_slave -c "SELECT pg_promote(wait := true);"
psql_slave -c "SELECT pg_is_in_recovery();"

log "Writing canary row on pg-slave (new primary)"
psql_slave -d testdb -c "INSERT INTO demo(note) VALUES ('written after failover, on promoted node');"

log "Letting pg-master finish crash recovery, then stopping it cleanly"
docker start pg-master
sleep 5
docker logs --tail 10 pg-master
docker stop pg-master

log "Granting pg_rewind permissions on pg-slave"
psql_slave -c "
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text) TO replicator;
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text, bigint, bigint) TO replicator;
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text, bigint, bigint, boolean) TO replicator;
GRANT EXECUTE ON FUNCTION pg_ls_dir(text, boolean, boolean) TO replicator;
GRANT EXECUTE ON FUNCTION pg_stat_file(text, boolean) TO replicator;
"

NETWORK=$(docker inspect pg-slave --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')
VOLUME=$(docker inspect pg-master --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}')

log "Running pg_rewind from a throwaway container (network=$NETWORK volume=$VOLUME)"
docker run --rm \
  --network "$NETWORK" \
  -v "$VOLUME:/var/lib/postgresql/data" \
  --user postgres \
  postgres:16 \
  pg_rewind --target-pgdata=/var/lib/postgresql/data \
    --source-server="host=pg-slave port=5432 user=replicator password=replpass dbname=postgres" \
    -R -P

log "Starting pg-master — it rejoins as a standby"
docker start pg-master
docker logs --tail 20 pg-master

log "Final verification"
psql_master -c "SELECT pg_is_in_recovery();"
psql_slave -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
psql_master -d testdb -c "SELECT * FROM demo;"

log "Drill complete: pg-slave is primary, pg-master rejoined as standby."
