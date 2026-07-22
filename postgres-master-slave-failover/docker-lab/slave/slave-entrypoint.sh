#!/bin/bash
# The official postgres image runs initdb on an empty PGDATA. The slave needs
# to pg_basebackup from the master instead, so this runs first and hands off
# to the normal entrypoint once PGDATA is populated.
set -e

if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
  echo ">>> PGDATA empty. Taking base backup from master..."
  until PGPASSWORD="$REPL_PASSWORD" pg_basebackup -h pg-master -D "$PGDATA" -U replicator -v -P -R --wal-method=stream
  do
    echo ">>> Waiting for master to become available..."
    sleep 2
  done
  chmod 0700 "$PGDATA"
  echo ">>> Base backup complete. standby.signal + primary_conninfo written by -R."
fi

exec docker-entrypoint.sh postgres
