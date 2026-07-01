#!/bin/bash
# ============================================================
#  MySQL / MariaDB Query Monitor
#  Output: clean table format | Saves to timestamped log file
#  NO auto-kill — use IDs to kill manually
# ============================================================

# ---------- CONFIG ----------
DB_USER="root"
DB_PASS=""               # leave empty for socket auth (OS root)
SLOW_THRESHOLD=60        # seconds
LOG_DIR="/root/logs"
# ----------------------------

MYSQL="mysql -u ${DB_USER} ${DB_PASS:+-p${DB_PASS}} --batch --skip-column-names"
TIMESTAMP=$(date "+%d-%m-%Y %H:%M:%S")
LOG_FILE="${LOG_DIR}/query_report_$(date +%d-%m-%Y_%H-%M-%S).log"

mkdir -p "${LOG_DIR}"

# Write to terminal + log file (strip colors for log)
log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# -------------------------------------------------------
# Check connection
# -------------------------------------------------------
$MYSQL -e "SELECT 1;" &>/dev/null || { echo "[ERROR] Cannot connect to MariaDB. Check credentials."; exit 1; }

# -------------------------------------------------------
# Header
# -------------------------------------------------------
log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║            MySQL / MariaDB  —  Query Monitor Report                     ║"
log "╠══════════════════════════════════════════════════════════════════════════╣"
log "║  Generated : $TIMESTAMP                                     ║"
log "║  Log File  : $LOG_FILE"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""

# -------------------------------------------------------
# Total Active Queries
# -------------------------------------------------------
TOTAL=$($MYSQL -e "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE COMMAND != 'Sleep';")
log "  Total Active Queries (excluding idle) : $TOTAL"
log ""

# -------------------------------------------------------
# Slow Queries Table
# -------------------------------------------------------
log "┌─────────────────────────────────────────────────────────────────────────┐"
log "│  SLOW QUERIES  —  running longer than ${SLOW_THRESHOLD} seconds                        │"
log "├────────┬──────────────────┬──────────┬────────────────┬────────────────┤"
log "│  ID    │  User@Host       │  Time(s) │  State         │  Query         │"
log "├────────┼──────────────────┼──────────┼────────────────┼────────────────┤"

SLOW=$($MYSQL -e "
  SELECT ID, CONCAT(USER,'@',HOST), TIME, STATE, SUBSTRING(IFNULL(INFO,'—'),1,30)
  FROM information_schema.PROCESSLIST
  WHERE COMMAND != 'Sleep'
    AND TIME >= $SLOW_THRESHOLD
    AND STATE NOT IN ('Locked','Updating','Waiting for lock',
                      'Waiting for table metadata lock','System lock')
  ORDER BY TIME DESC;")

if [ -z "$SLOW" ]; then
    log "│  No slow queries found.                                                 │"
else
    while IFS=$'\t' read -r ID UH TIME STATE INFO; do
        printf "│  %-6s│  %-16s│  %-8s│  %-14s│  %-14s│\n" \
            "$ID" "$UH" "${TIME}s" "$STATE" "$INFO" | tee -a "$LOG_FILE"
    done <<< "$SLOW"
fi

log "└────────┴──────────────────┴──────────┴────────────────┴────────────────┘"
log ""

# -------------------------------------------------------
# Stuck / Locked Queries Table
# -------------------------------------------------------
log "┌─────────────────────────────────────────────────────────────────────────┐"
log "│  STUCK / LOCKED QUERIES                                                 │"
log "├────────┬──────────────────┬──────────┬──────────────────────────────────┤"
log "│  ID    │  User@Host       │  Time(s) │  Query                           │"
log "├────────┼──────────────────┼──────────┼──────────────────────────────────┤"

STUCK=$($MYSQL -e "
  SELECT ID, CONCAT(USER,'@',HOST), TIME, SUBSTRING(IFNULL(INFO,'—'),1,40)
  FROM information_schema.PROCESSLIST
  WHERE COMMAND != 'Sleep'
    AND STATE IN ('Locked','Updating','Waiting for lock',
                  'Waiting for table metadata lock','System lock')
  ORDER BY TIME DESC;")

if [ -z "$STUCK" ]; then
    log "│  No stuck queries found.                                                │"
else
    while IFS=$'\t' read -r ID UH TIME INFO; do
        printf "│  %-6s│  %-16s│  %-8s│  %-34s│\n" \
            "$ID" "$UH" "${TIME}s" "$INFO" | tee -a "$LOG_FILE"
    done <<< "$STUCK"
fi

log "└────────┴──────────────────┴──────────┴──────────────────────────────────┘"
log ""

# -------------------------------------------------------
# Lock Chain Table
# -------------------------------------------------------
log "┌─────────────────────────────────────────────────────────────────────────┐"
log "│  LOCK CHAIN  —  who is blocking whom                                    │"
log "├──────────────┬──────────────────────────────────┬──────────┬────────────┤"
log "│  Waiting ID  │  Blocking ID                     │  Wait(s) │  Kill Cmd  │"
log "├──────────────┼──────────────────────────────────┼──────────┼────────────┤"

LOCKS=$($MYSQL -e "
  SELECT r.trx_mysql_thread_id,
         b.trx_mysql_thread_id,
         TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW())
  FROM information_schema.INNODB_LOCK_WAITS w
  JOIN information_schema.INNODB_TRX r ON w.requesting_trx_id = r.trx_id
  JOIN information_schema.INNODB_TRX b ON w.blocking_trx_id   = b.trx_id;
" 2>/dev/null)

if [ -z "$LOCKS" ]; then
    log "│  No lock waits detected.                                                │"
else
    while IFS=$'\t' read -r W_ID B_ID WAIT; do
        printf "│  %-12s│  %-32s│  %-8s│  %-10s│\n" \
            "$W_ID" "$B_ID" "${WAIT}s" "KILL $B_ID;" | tee -a "$LOG_FILE"
    done <<< "$LOCKS"
fi

log "└──────────────┴──────────────────────────────────┴──────────┴────────────┘"
log ""
log "  Report saved : $LOG_FILE"
log ""
