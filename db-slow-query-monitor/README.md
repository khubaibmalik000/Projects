# DB Slow Query Monitor

A bash script that reports on the current health of a MySQL/MariaDB server by inspecting its process list. It highlights slow-running queries and lock contention so you can spot and manually resolve problems — it does **not** auto-kill anything.

## What it does

- Connects to MySQL/MariaDB and confirms the connection is alive.
- Reports the total number of active (non-idle) queries.
- **Slow Queries** table — lists queries running longer than a configurable threshold (default 60s), excluding ones already blocked on a lock.
- **Stuck / Locked Queries** table — lists queries currently waiting on locks or metadata locks.
- **Lock Chain** table — shows which transaction is blocking which (via `INNODB_LOCK_WAITS`), along with the wait time and the exact `KILL` command needed to clear it.
- Prints the report to the terminal and also saves a timestamped copy to a log file.

## Usage

```bash
chmod +x monitor.sh
./monitor.sh
```

## Configuration

Edit the variables at the top of `monitor.sh`:

| Variable         | Description                                      | Default      |
|------------------|---------------------------------------------------|--------------|
| `DB_USER`        | MySQL user                                       | `root`       |
| `DB_PASS`        | MySQL password (leave empty for socket auth)     | *(empty)*    |
| `SLOW_THRESHOLD` | Seconds before a query is flagged as slow        | `60`         |
| `LOG_DIR`        | Directory where report logs are saved            | `/root/logs` |

## Requirements

- `bash`
- `mysql` client with access to `information_schema`
