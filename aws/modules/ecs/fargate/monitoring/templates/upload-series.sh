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

# The volume is created root-owned; Prometheus runs as nobody and writes here.
mkdir -p "$OUTBOX" && chmod 1777 "$OUTBOX"

printf '%s' "$GCP_CREDENTIAL_CONFIG" > /tmp/gcp-credential-config.json
export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/tmp/gcp-credential-config.json

while true; do
    sleep "$POLL"

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
        if gcloud storage cp --quiet "$FILE" "gs://${GCS_BUCKET}/${GCS_PREFIX}/${NAMESPACE}/"; then
            rm -f "$FILE"
        else
            echo "upload of $(basename "$FILE") failed, retrying next cycle"
        fi
    done
done
