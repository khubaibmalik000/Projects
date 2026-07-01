# Postgres → S3 Backup Pipeline

A backup pipeline for PostgreSQL that combines weekly full backups with continuous WAL (Write-Ahead Log) archiving, and ships both to S3 for durable, off-site, point-in-time-recoverable storage.

## How it works

- **WAL archiving**: PostgreSQL is configured to archive every WAL segment to a local directory as it's generated (`archive_mode = on`), enabling point-in-time recovery.
- **Full backup**: Once a week (Saturday), the script takes a full base backup with `pg_basebackup`, compresses it, and uploads it to S3.
- **Incremental WAL sync**: Every run, the script uploads any WAL files not already present in S3, skipping ones already uploaded to avoid duplicates.
- **Logging**: All actions are logged to `/var/log/pg_backup.log`.

## Setup

### 1. Enable WAL archiving

Edit the Postgres config (path may vary by version):

```bash
sudo nano /etc/postgresql/18/main/postgresql.conf
```

Add:

```
wal_level = replica
archive_mode = on
archive_command = 'cp %p /var/lib/postgresql/wal_archive/%f'
```

Create the archive directory and restart Postgres:

```bash
sudo mkdir -p /var/lib/postgresql/wal_archive
sudo chown postgres:postgres /var/lib/postgresql/wal_archive
sudo systemctl restart postgresql
```

Verify WAL archiving is working:

```bash
sudo -u postgres psql -c "SELECT pg_switch_wal();"
ls /var/lib/postgresql/wal_archive
```

### 2. Configure AWS CLI

```bash
aws configure
```

You'll need an Access Key ID, Secret Access Key, default region, and output format (`json`). Make sure an S3 bucket already exists for backups.

### 3. Configure the script

Edit the `CONFIG` section at the top of `pg_backup.sh` and set `S3_BUCKET` to your actual bucket (e.g. `s3://my-company-backups/postgres`).

### 4. Run it

```bash
chmod +x pg_backup.sh
./pg_backup.sh
```

### 5. Schedule it (cron)

Run daily (full backup logic only triggers on Saturdays):

```
0 2 * * * /path/to/pg_backup.sh
```

## Requirements

- PostgreSQL with WAL archiving enabled
- AWS CLI, configured with S3 access
- `sudo` access to run as the `postgres` user
