# Transcript Count Autoscaler

A bash-based custom autoscaler for a Kubernetes deployment that processes call-recording transcripts. Instead of scaling on CPU/memory like the standard HPA, it scales based on a **backlog metric pulled directly from MySQL** — the number of recordings still pending transcription.

## What it does

1. Queries MySQL for the count of `call_recordings` rows not yet in a terminal `transcript_status` (`failed`/`done`).
2. Calculates the number of pods needed (`ceil(pending / COUNT_PER_POD)`), capped at `MAX_PODS`.
3. Compares against the deployment's current replica count — does nothing if they already match.
4. Scales the deployment up or down via `kubectl scale`, with retries on failure.
5. Verifies the rollout completed successfully (`kubectl rollout status`).
6. Applies a cooldown window to avoid thrashing (rapid repeated scaling).
7. Sends Telegram notifications on start failures, scaling actions, and rollout failures.
8. Supports a mock-DB mode (`USE_MOCK_DB`) for testing the scaling logic without a live database.

## Usage

Run on a schedule (e.g. via cron every minute):

```bash
chmod +x transcript-autoscaler.sh
*/1 * * * * /path/to/transcript-autoscaler.sh
```

## Configuration

Edit the variables at the top of the script:

| Variable         | Description                                       | Default         |
|------------------|-----------------------------------------------------|------------------|
| `DB_HOST`/`DB_USER`/`DB_PASS`/`DB_NAME` | MySQL connection details               | placeholders / `reporting_db` |
| `NAMESPACE` / `DEPLOYMENT` | Target Kubernetes deployment to scale    | `test` / `recor` |
| `MAX_PODS`       | Upper bound on replica count                       | `25`             |
| `COUNT_PER_POD`  | How many pending transcripts each pod can handle   | `50000`          |
| `COOLDOWN_SECONDS` | Minimum time between scaling actions             | `60`             |
| `BOT_TOKEN` / `CHAT_ID` | Telegram bot token and chat ID for alerts    | placeholders     |

## Requirements

- `mysql` client
- `kubectl` with access to the target cluster
- A Telegram bot token and chat ID for notifications
