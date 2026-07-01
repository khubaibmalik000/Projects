#!/usr/bin/env bash
# ==============================================================================
#  FILE        : cleanup_before_date.sh
#  DESCRIPTION : Connects to a MariaDB database, prompts for a cutoff date,
#                deletes all rows older than that date from known tables,
#                and prints a detailed summary report.
#  USAGE       : ./cleanup_before_date.sh
#  AUTHOR      : testuser
#  DATABASE    : dummy_testdb
#  VERSION     : 1.0.0
#  UPDATED     : 2026-06-12
# ==============================================================================

# ------------------------------------------------------------------------------
# [CONFIG] Database connection settings
# You can override any of these by setting environment variables before running:
#   DB_HOST=10.0.0.5 DB_USER=admin ./cleanup_before_date.sh
# ------------------------------------------------------------------------------
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-testuser}"
DB_PASS="${DB_PASS:-Test@1234}"
DB_NAME="dummy_testdb"

# ------------------------------------------------------------------------------
# [CONFIG] Tables to clean up — format: TABLE_NAME:DATE_COLUMN
# Add or remove entries here if your schema changes
# ------------------------------------------------------------------------------
TABLES=(
  "orders:created_at"
  "user_events:event_date"
  "logs:logged_at"
  "audit_trail:audit_date"
  "notifications:sent_at"
)

# ------------------------------------------------------------------------------
# [COLORS] Terminal color codes for pretty output
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ------------------------------------------------------------------------------
# [FUNCTION] mysql_cmd
# Wrapper to run mysql commands with the configured credentials
# ------------------------------------------------------------------------------
mysql_cmd() {
  mysql -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"$DB_PASS" \
        "$DB_NAME" "$@" 2>/dev/null
}

# ------------------------------------------------------------------------------
# [FUNCTION] print_banner
# Prints the welcome banner at script start
# ------------------------------------------------------------------------------
print_banner() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}║${RESET}${BOLD}          MariaDB — Date-Based Data Cleanup               ${CYAN}║${RESET}"
  echo -e "${CYAN}║${RESET}${DIM}          Database : ${DB_NAME} @ ${DB_HOST}:${DB_PORT}              ${CYAN}║${RESET}"
  echo -e "${CYAN}║${RESET}${DIM}          User     : ${DB_USER}                                 ${CYAN}║${RESET}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

# ------------------------------------------------------------------------------
# [FUNCTION] check_connection
# Verifies that MariaDB is reachable before doing anything
# ------------------------------------------------------------------------------
check_connection() {
  echo -e "${YELLOW}  Checking database connection...${RESET}"
  if ! mysql_cmd -e "SELECT 1;" &>/dev/null; then
    echo ""
    echo -e "${RED}  ERROR: Cannot connect to MariaDB!${RESET}"
    echo -e "${DIM}    Host : ${DB_HOST}:${DB_PORT}${RESET}"
    echo -e "${DIM}    User : ${DB_USER}${RESET}"
    echo -e "${DIM}    Tip  : Set DB_HOST, DB_PORT, DB_USER, DB_PASS as env vars if needed.${RESET}"
    echo ""
    exit 1
  fi
  echo -e "${GREEN}  Connected successfully to '${DB_NAME}'.${RESET}"
  echo ""
}

# ------------------------------------------------------------------------------
# [FUNCTION] ask_date
# Prompts the user for a cutoff date and validates the format
# ------------------------------------------------------------------------------
ask_date() {
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo -e "${BOLD}  STEP 1 — Enter Cutoff Date${RESET}"
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo -e "  Rows with a date strictly before this date will be deleted."
  echo ""

  while true; do
    read -rp "  Enter date [YYYY-MM-DD]: " CUTOFF_DATE

    # Validate format with regex
    if [[ "$CUTOFF_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      # Validate it is a real calendar date using the date command
      VALID=$(date -d "$CUTOFF_DATE" +%Y-%m-%d 2>/dev/null)
      if [[ -n "$VALID" ]]; then
        break
      fi
    fi

    echo -e "${RED}  Invalid date. Please use YYYY-MM-DD format (e.g. 2025-01-01).${RESET}"
  done

  echo ""
  echo -e "  ${BOLD}Cutoff date set to: ${YELLOW}${CUTOFF_DATE}${RESET}"
  echo ""
}

# ------------------------------------------------------------------------------
# [FUNCTION] preview_counts
# Shows how many rows exist and how many will be deleted per table
# ------------------------------------------------------------------------------
preview_counts() {
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo -e "${BOLD}  STEP 2 — Preview: Rows to be Deleted${RESET}"
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo ""

  mysql_cmd --table -e "
    SELECT 'orders'         AS \`table\`,
           COUNT(*)         AS total_rows,
           SUM(created_at  < '${CUTOFF_DATE}') AS rows_to_delete
    FROM orders
    UNION ALL
    SELECT 'user_events',
           COUNT(*),
           SUM(event_date  < '${CUTOFF_DATE}')
    FROM user_events
    UNION ALL
    SELECT 'logs',
           COUNT(*),
           SUM(logged_at   < '${CUTOFF_DATE}')
    FROM logs
    UNION ALL
    SELECT 'audit_trail',
           COUNT(*),
           SUM(audit_date  < '${CUTOFF_DATE}')
    FROM audit_trail
    UNION ALL
    SELECT 'notifications',
           COUNT(*),
           SUM(sent_at     < '${CUTOFF_DATE}')
    FROM notifications;"

  echo ""
}

# ------------------------------------------------------------------------------
# [FUNCTION] confirm_deletion
# Asks the user to confirm before any data is deleted
# ------------------------------------------------------------------------------
confirm_deletion() {
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo -e "${BOLD}  STEP 3 — Confirm Deletion${RESET}"
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo ""
  echo -e "${RED}  WARNING: This action cannot be undone!${RESET}"
  echo -e "  All rows with a date before ${BOLD}${CUTOFF_DATE}${RESET} will be permanently deleted."
  echo ""

  read -rp "  Type 'yes' to confirm, anything else to abort: " CONFIRM
  echo ""

  if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${YELLOW}  Aborted by user. No data was deleted.${RESET}"
    echo ""
    exit 0
  fi
}

# ------------------------------------------------------------------------------
# [FUNCTION] run_deletions
# Loops through all tables and deletes rows older than the cutoff date
# ------------------------------------------------------------------------------
run_deletions() {
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo -e "${BOLD}  STEP 4 — Running Deletions${RESET}"
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo ""

  declare -gA DELETED_ROWS
  GRAND_TOTAL=0

  for ENTRY in "${TABLES[@]}"; do
    TABLE="${ENTRY%%:*}"
    DATE_COL="${ENTRY##*:}"

    echo -ne "  ${BOLD}${TABLE}${RESET} (column: ${DATE_COL}) ... "

    mysql_cmd -e "DELETE FROM \`${TABLE}\` WHERE \`${DATE_COL}\` < '${CUTOFF_DATE}';"

    ROWS=$(mysql_cmd -sN -e "SELECT ROW_COUNT();")
    DELETED_ROWS[$TABLE]=$ROWS
    GRAND_TOTAL=$((GRAND_TOTAL + ROWS))

    if [[ "$ROWS" -gt 0 ]]; then
      echo -e "${GREEN}${ROWS} row(s) deleted.${RESET}"
    else
      echo -e "${YELLOW}0 rows deleted (no data before ${CUTOFF_DATE}).${RESET}"
    fi
  done

  echo ""
}

# ------------------------------------------------------------------------------
# [FUNCTION] print_summary
# Prints a final report of what was deleted and what remains
# ------------------------------------------------------------------------------
print_summary() {
  echo -e "${CYAN}============================================================${RESET}"
  echo -e "${BOLD}                    CLEANUP SUMMARY${RESET}"
  echo -e "${CYAN}============================================================${RESET}"
  echo -e "  Database  : ${BOLD}${DB_NAME}${RESET}"
  echo -e "  Cutoff    : rows with date < ${BOLD}${CUTOFF_DATE}${RESET} were removed"
  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  printf "  %-22s  %-15s  %s\n" "TABLE" "ROWS DELETED" "STATUS"
  printf "  %-22s  %-15s  %s\n" "----------------------" "---------------" "----------"

  for ENTRY in "${TABLES[@]}"; do
    TABLE="${ENTRY%%:*}"
    COUNT="${DELETED_ROWS[$TABLE]:-0}"
    if [[ "$COUNT" -gt 0 ]]; then
      printf "  ${GREEN}%-22s  %-15s  Cleaned${RESET}\n" "$TABLE" "$COUNT"
    else
      printf "  %-22s  %-15s  Nothing to delete\n" "$TABLE" "$COUNT"
    fi
  done

  echo -e "${CYAN}------------------------------------------------------------${RESET}"
  echo -e "  ${BOLD}Total rows deleted : ${GREEN}${GRAND_TOTAL}${RESET}"
  echo -e "${CYAN}============================================================${RESET}"
  echo ""

  echo -e "${BLUE}  Remaining row counts after cleanup:${RESET}"
  echo ""
  mysql_cmd --table -e "
    SELECT 'orders'         AS \`table\`, COUNT(*) AS remaining_rows FROM orders
    UNION ALL SELECT 'user_events',   COUNT(*) FROM user_events
    UNION ALL SELECT 'logs',          COUNT(*) FROM logs
    UNION ALL SELECT 'audit_trail',   COUNT(*) FROM audit_trail
    UNION ALL SELECT 'notifications', COUNT(*) FROM notifications;"

  echo ""
  echo -e "${GREEN}  Cleanup complete. All done!${RESET}"
  echo ""
}

# ==============================================================================
# [MAIN] Script entry point — runs all steps in order
# ==============================================================================
main() {
  print_banner
  check_connection
  ask_date
  preview_counts
  confirm_deletion
  run_deletions
  print_summary
}

main "$@"
