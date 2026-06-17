#!/bin/bash
set -euo pipefail

CLUSTERS=("$CLUSTER_1_NAME" "$CLUSTER_2_NAME")

# The cross-cluster IPSec tunnel takes a few minutes to establish even after the
# Submariner addons report Available=True. Poll until both clusters report an
# established connection, up to a bounded timeout.
TIMEOUT_SECONDS="${SUBCTL_VERIFY_TIMEOUT_SECONDS:-600}"
POLL_INTERVAL_SECONDS="${SUBCTL_VERIFY_POLL_INTERVAL_SECONDS:-15}"
deadline=$((SECONDS + TIMEOUT_SECONDS))

# Check the status of both clusters
while true; do
    all_connected=true

    for CLUSTER_NAME in "${CLUSTERS[@]}"; do
        # `subctl show all` exits non-zero while no connection exists yet; tolerate
        # that here so the retry loop is not aborted by `set -e` on the first poll.
        STATUS=$(subctl show all --contexts "$CLUSTER_NAME" 2>&1 || true)
        echo "Status of Cluster ($CLUSTER_NAME):"
        echo "$STATUS"

        if echo "$STATUS" | grep -q "All connections (1) are established" && \
           echo "$STATUS" | grep -q " connected "; then
            echo "Gateway and Connection for $CLUSTER_NAME are correctly established!"
        else
            echo "$CLUSTER_NAME is not fully connected, retrying..."
            all_connected=false
        fi
    done

    if [ "$all_connected" = true ]; then
        echo "Both clusters are correctly connected!"
        exit 0
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "Submariner connections were not established within ${TIMEOUT_SECONDS}s." >&2
        exit 1
    fi

    sleep "$POLL_INTERVAL_SECONDS"
done
