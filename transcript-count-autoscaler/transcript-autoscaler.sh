#!/bin/bash

############################################################
# Transcript Autoscaler
# Namespace   : test
# Deployment  : recor
############################################################

#########################
# CONFIGURATION
#########################

MYSQL="/usr/bin/mysql"
KUBECTL="kubectl"

DB_HOST="CHANGE_ME_DB_HOST"
DB_USER="CHANGE_ME_DB_USER"
DB_PASS="CHANGE_ME_DB_PASSWORD"
DB_NAME="reporting_db"

NAMESPACE="test"
DEPLOYMENT="recor"

MAX_PODS=25
COUNT_PER_POD=50000

LOG_FILE="/var/log/transcript-autoscaler.log"

RETRY_COUNT=3
RETRY_DELAY=5

#########################
# TELEGRAM CONFIG
#########################

BOT_TOKEN="CHANGE_ME_TELEGRAM_BOT_TOKEN"
CHAT_ID="CHANGE_ME_TELEGRAM_CHAT_ID"

#########################
# TEST / PROD SWITCH
#########################

USE_MOCK_DB=false
MOCK_COUNT=0

#########################
# COOLDOWN SETTINGS
#########################

COOLDOWN_FILE="/tmp/transcript-autoscaler.lock"
COOLDOWN_SECONDS=60

#########################
# LOGGING FUNCTION
#########################

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" >> "$LOG_FILE"
}

#########################
# TELEGRAM FUNCTION
#########################

send_telegram() {

    MESSAGE="$1"

    curl -s -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${MESSAGE}" \
        >/dev/null 2>&1
}

#########################
# CHECK MYSQL CLIENT
#########################

if [ ! -x "$MYSQL" ]; then

    log_message "mysql client not found"

    send_telegram "❌ Transcript Autoscaler

mysql client not found:
$MYSQL"

    exit 1
fi

#########################
# CHECK KUBECTL
#########################

if ! command -v kubectl >/dev/null 2>&1; then

    log_message "kubectl not found"

    send_telegram "❌ Transcript Autoscaler

kubectl not found"

    exit 1
fi

#########################
# GET COUNT (MOCK OR REAL)
#########################

if [ "$USE_MOCK_DB" = "true" ]; then

    COUNT=$MOCK_COUNT

    log_message "Using mock DB count: $COUNT"

else

    QUERY="SELECT COUNT(*) FROM call_recordings WHERE transcript_status NOT IN ('failed','done');"

    COUNT=$($MYSQL --batch --skip-column-names \
        -h "$DB_HOST" \
        -u "$DB_USER" \
        -p"$DB_PASS" \
        "$DB_NAME" \
        -e "$QUERY")

    MYSQL_RC=$?

    if [ $MYSQL_RC -ne 0 ]; then

        log_message "MySQL query failed"

        send_telegram "❌ Transcript Autoscaler

MySQL query failed"

        exit 1
    fi
fi

#########################
# VALIDATE COUNT
#########################

COUNT=$(echo "$COUNT" | xargs)

if [[ -z "$COUNT" || ! "$COUNT" =~ ^[0-9]+$ ]]; then

    log_message "Invalid count: $COUNT"

    send_telegram "❌ Transcript Autoscaler

Invalid transcript count:
$COUNT"

    exit 1
fi

#########################
# COOLDOWN CHECK
#########################

if [ -f "$COOLDOWN_FILE" ]; then

    LAST_RUN=$(cat "$COOLDOWN_FILE")
    NOW=$(date +%s)

    DIFF=$((NOW - LAST_RUN))

    if [ "$DIFF" -lt "$COOLDOWN_SECONDS" ]; then

        log_message "Cooldown active, skipping scaling"

        exit 0
    fi
fi

#########################
# CALCULATE REQUIRED PODS
#########################

REQUIRED_PODS=$(( (COUNT + COUNT_PER_POD - 1) / COUNT_PER_POD ))

if [ "$REQUIRED_PODS" -lt 1 ]; then
    REQUIRED_PODS=1
fi

if [ "$REQUIRED_PODS" -gt "$MAX_PODS" ]; then
    REQUIRED_PODS=$MAX_PODS
fi

#########################
# GET CURRENT REPLICAS
#########################

CURRENT_PODS=$($KUBECTL get deployment "$DEPLOYMENT" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.replicas}')

if [[ -z "$CURRENT_PODS" || ! "$CURRENT_PODS" =~ ^[0-9]+$ ]]; then

    log_message "Failed to fetch replicas"

    send_telegram "❌ Transcript Autoscaler

Unable to fetch deployment replicas

Namespace: $NAMESPACE
Deployment: $DEPLOYMENT"

    exit 1
fi

#########################
# NO SCALING REQUIRED
#########################

if [ "$CURRENT_PODS" -eq "$REQUIRED_PODS" ]; then

    log_message "No scaling needed. Pending=$COUNT Replicas=$CURRENT_PODS"

    exit 0
fi

#########################
# DETERMINE ACTION
#########################

if [ "$REQUIRED_PODS" -gt "$CURRENT_PODS" ]; then
    ACTION="UP"
else
    ACTION="DOWN"
fi

#########################
# SCALE WITH RETRIES
#########################

SUCCESS=0

for ((i=1; i<=RETRY_COUNT; i++))
do

    $KUBECTL scale deployment "$DEPLOYMENT" \
        --replicas="$REQUIRED_PODS" \
        -n "$NAMESPACE"

    SCALE_RC=$?

    if [ $SCALE_RC -eq 0 ]; then

        SUCCESS=1

        log_message "Scaling $ACTION successful. Pending=$COUNT OldPods=$CURRENT_PODS NewPods=$REQUIRED_PODS"

        #########################
        # SET COOLDOWN
        #########################

        date +%s > "$COOLDOWN_FILE"

        #########################
        # ROLLOUT VERIFICATION
        #########################

        $KUBECTL rollout status deployment "$DEPLOYMENT" \
            -n "$NAMESPACE" \
            --timeout=60s >/dev/null 2>&1

        ROLLOUT_RC=$?

        if [ $ROLLOUT_RC -ne 0 ]; then

            log_message "Rollout failed after scaling"

            send_telegram "❌ Transcript Autoscaler

Rollout failed after scaling

Namespace: $NAMESPACE
Deployment: $DEPLOYMENT
Desired Replicas: $REQUIRED_PODS"

            exit 1
        fi

        #########################
        # TELEGRAM SUCCESS ALERT
        #########################

        send_telegram "🚀 Transcript Autoscaler

Scaling Action: $ACTION

Namespace: $NAMESPACE
Deployment: $DEPLOYMENT

Pending Transcripts: $COUNT

Old Replicas: $CURRENT_PODS
New Replicas: $REQUIRED_PODS"

        echo "Scaled $ACTION from $CURRENT_PODS to $REQUIRED_PODS"

        exit 0
    fi

    log_message "Scaling attempt $i failed"

    sleep "$RETRY_DELAY"

done

#########################
# FINAL FAILURE
#########################

log_message "Scaling failed after retries"

send_telegram "❌ Transcript Autoscaler

Scaling failed after $RETRY_COUNT retries

Namespace: $NAMESPACE
Deployment: $DEPLOYMENT"

exit 1
