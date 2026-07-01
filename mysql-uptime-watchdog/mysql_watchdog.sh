#!/bin/bash

HOST="127.0.0.1"
PORT=3306

BOT_TOKEN="CHANGE_ME_TELEGRAM_BOT_TOKEN"
CHAT_ID="CHANGE_ME_TELEGRAM_CHAT_ID"

STATE="UNKNOWN"

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$1" > /dev/null
}

echo "🚀 MySQL Watchdog Started..."

send_telegram "🚀 MySQL Monitor Started"

while true
do
    NOW=$(date "+%Y-%m-%d %H:%M:%S")

    mysqladmin ping -h $HOST -P $PORT --silent
    STATUS=$?

    # DB DOWN
    if [ $STATUS -ne 0 ]; then
        if [ "$STATE" != "DOWN" ]; then
            MSG="🚨 [$NOW] CRITICAL: MySQL is DOWN"
            echo "$MSG"
            send_telegram "$MSG"
        fi
        STATE="DOWN"

    else
        # DB RECOVERED
        if [ "$STATE" = "DOWN" ]; then
            MSG="⚠️ [$NOW] ALERT: MySQL HAS RESTARTED"
            echo "$MSG"
            send_telegram "$MSG"
        fi
        STATE="UP"
    fi

    sleep 15
done
