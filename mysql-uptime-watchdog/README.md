# MySQL Uptime Watchdog

A lightweight bash daemon that continuously pings a MySQL/MariaDB server and sends Telegram alerts the moment it goes down — and again when it recovers.

## What it does

- Polls the database every 15 seconds using `mysqladmin ping`.
- Tracks state transitions (`UP` → `DOWN` → `UP`) so it only alerts *once* per transition, not on every failed check.
- Sends a Telegram message on startup, on outage detection (🚨 CRITICAL), and on recovery (⚠️ ALERT: restarted).

## Usage

```bash
chmod +x mysql_watchdog.sh
./mysql_watchdog.sh &
```

Run it under `systemd`, `screen`, or `nohup` for persistence across sessions/reboots.

## Configuration

Edit the variables at the top of the script:

| Variable    | Description                          | Default          |
|-------------|---------------------------------------|-------------------|
| `HOST`      | Database host to ping                | `127.0.0.1`       |
| `PORT`      | Database port                        | `3306`            |
| `BOT_TOKEN` | Telegram bot token (from BotFather)  | *(placeholder)*   |
| `CHAT_ID`   | Telegram chat/channel ID to notify   | *(placeholder)*   |

## Requirements

- `mysqladmin` client
- `curl`
- A Telegram bot token and target chat ID
