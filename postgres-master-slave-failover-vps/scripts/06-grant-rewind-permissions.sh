#!/usr/bin/env bash
# Run locally on the (new) primary. Grants the replication role exactly the
# functions pg_rewind needs — not superuser — so a failed-back node can rejoin.
# Usage: REPLICATOR_USER=replicator ./06-grant-rewind-permissions.sh
set -euo pipefail

REPLICATOR_USER="${REPLICATOR_USER:-replicator}"

sudo -u postgres psql -c "
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text) TO ${REPLICATOR_USER};
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text, bigint, bigint) TO ${REPLICATOR_USER};
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text, bigint, bigint, boolean) TO ${REPLICATOR_USER};
GRANT EXECUTE ON FUNCTION pg_ls_dir(text, boolean, boolean) TO ${REPLICATOR_USER};
GRANT EXECUTE ON FUNCTION pg_stat_file(text, boolean) TO ${REPLICATOR_USER};
"
