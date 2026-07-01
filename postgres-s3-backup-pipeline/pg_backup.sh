#!/bin/bash
set -e  # stop on error

# ---------- CONFIG ----------
BACKUP_DIR="/var/backups/postgres"
S3_BUCKET="s3://your-bucket-name/postgres"
WAL_DIR="/var/lib/postgresql/wal_archive"
LOG_FILE="/var/log/pg_backup.log"
# -----------------------------

DATE=$(date +%Y-%m-%d)
DAY=$(date +%u)

mkdir -p "$BACKUP_DIR"

echo "===== BACKUP START: $DATE =====" | tee -a "$LOG_FILE"

# =========================
# FULL BACKUP (SATURDAY ONLY)
# =========================
if [ "$DAY" -eq 6 ]; then
    echo "[INFO] Running FULL BACKUP..." | tee -a "$LOG_FILE"

    BACKUP_PATH="$BACKUP_DIR/full_$DATE"

    sudo -u postgres pg_basebackup \
        -D "$BACKUP_PATH" \
        -Ft -z -P

    FILE="$BACKUP_PATH.tar.gz"

    tar -czf "$FILE" -C "$BACKUP_DIR" "full_$DATE"

    aws s3 cp "$FILE" "$S3_BUCKET/full/" >> "$LOG_FILE" 2>&1

    echo "[SUCCESS] FULL BACKUP COMPLETED" | tee -a "$LOG_FILE"
else
    echo "[INFO] Skipping full backup (not Saturday)" | tee -a "$LOG_FILE"
fi

# =========================
# WAL INCREMENTAL SYNC
# =========================
echo "[INFO] Syncing WAL files..." | tee -a "$LOG_FILE"

for file in "$WAL_DIR"/*; do
    if [ -f "$file" ]; then
        FILE_NAME=$(basename "$file")

        # skip if already uploaded (avoid duplicates)
        if aws s3 ls "$S3_BUCKET/wal/$FILE_NAME" >/dev/null 2>&1; then
            echo "[SKIP] $FILE_NAME already exists" | tee -a "$LOG_FILE"
        else
            aws s3 cp "$file" "$S3_BUCKET/wal/" >> "$LOG_FILE" 2>&1
            echo "[UPLOAD] $FILE_NAME" | tee -a "$LOG_FILE"
        fi
    fi
done

echo "===== BACKUP COMPLETE =====" | tee -a "$LOG_FILE"
