#!/bin/sh
# Move the files the Prometheus container dumps into OUTBOX to a GCS bucket.
#
# Authenticates through Google workload identity federation with the task
# role: GCP_CREDENTIAL_CONFIG is an external_account credential configuration,
# not a key. Fargate serves task-role credentials over HTTP, which the Google
# auth library does not read, so they are exported as the environment
# variables it does read before each cycle.

OUTBOX="${OUTBOX:-/outbox}"
POLL="${UPLOAD_POLL_SECONDS:-60}"
MAX_AGE_MINUTES="${MAX_AGE_MINUTES:-360}"

# The volume is created root-owned; Prometheus runs as nobody and writes here.
mkdir -p "$OUTBOX" && chmod 1777 "$OUTBOX"

printf '%s' "$GCP_CREDENTIAL_CONFIG" > /tmp/gcp-credential-config.json
export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/tmp/gcp-credential-config.json

while true; do
    sleep "$POLL"

    # Bound the backlog when uploads keep failing. The receiving Prometheus
    # rejects samples older than its 6h out-of-order window, so an older
    # batch can never be imported; dropping it keeps a long GCS or auth
    # outage from filling the task storage the TSDB lives on.
    find "$OUTBOX" -type f -mmin +"$MAX_AGE_MINUTES" -print -delete |
        sed 's/^/dropped stale batch: /'

    set -- "$OUTBOX"/*.prom.gz
    [ -e "$1" ] || continue

    if ! CREDS=$(curl -sf "http://169.254.170.2${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}"); then
        echo "task role credentials unavailable, retrying next cycle"
        continue
    fi
    AWS_ACCESS_KEY_ID=$(printf '%s' "$CREDS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["AccessKeyId"])')
    AWS_SECRET_ACCESS_KEY=$(printf '%s' "$CREDS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["SecretAccessKey"])')
    AWS_SESSION_TOKEN=$(printf '%s' "$CREDS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Token"])')
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

    for FILE in "$@"; do
        # One directory per UTC day, so the importer only lists the last two
        # days rather than the whole, never-expiring history.
        if gcloud storage cp --quiet "$FILE" "gs://${GCS_BUCKET}/${GCS_PREFIX}/$(date -u +%F)/${NAMESPACE}/"; then
            rm -f "$FILE"
        else
            echo "upload of $(basename "$FILE") failed, retrying next cycle"
        fi
    done
done
