# MariaDB Date-Based Cleanup

An interactive bash script for safely purging old rows from a MariaDB database. It walks through a preview-then-confirm flow so you can see exactly what will be deleted before anything happens.

## What it does

1. **Connects** to MariaDB and verifies the connection before doing anything.
2. **Asks for a cutoff date** (`YYYY-MM-DD`), validating both the format and that it's a real calendar date.
3. **Previews** row counts per table — total rows vs. how many are older than the cutoff — so you can sanity-check the impact first.
4. **Confirms** with the user (must type `yes`) before deleting anything.
5. **Runs the deletions** across all configured tables and tracks how many rows were removed from each.
6. **Prints a summary report**, including remaining row counts per table after cleanup.

Tables cleaned (configurable via the `TABLES` array): `orders`, `user_events`, `logs`, `audit_trail`, `notifications` — each mapped to its own date column.

## Usage

```bash
chmod +x cleanup_before_date.sh
./cleanup_before_date.sh
```

You'll be prompted for a cutoff date, shown a preview, and asked to confirm before any row is deleted.

## Configuration

Connection settings default to a local test database but can be overridden with environment variables:

```bash
DB_HOST=10.0.0.5 DB_USER=admin DB_PASS=yourpassword ./cleanup_before_date.sh
```

| Variable  | Description           | Default         |
|-----------|------------------------|-----------------|
| `DB_HOST` | Database host          | `127.0.0.1`     |
| `DB_PORT` | Database port          | `3306`          |
| `DB_USER` | Database user          | `testuser`      |
| `DB_PASS` | Database password      | *(test default)*|

`DB_NAME` and the list of tables/date-columns are set directly in the script.

## Requirements

- `bash`
- `mysql` client
- MariaDB/MySQL server access with `DELETE` privileges on the target tables
