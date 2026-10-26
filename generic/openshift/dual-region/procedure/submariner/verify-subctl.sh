#!/bin/bash
set -euo pipefail

: "${CLUSTER_1_NAME:?CLUSTER_1_NAME must be set}" "${CLUSTER_2_NAME:?CLUSTER_2_NAME must be set}"

CLUSTERS=("$CLUSTER_1_NAME" "$CLUSTER_2_NAME")

# The cross-cluster IPSec tunnel takes a few minutes to establish even after the
# Submariner addons report Available=True. Poll until both clusters report an
# established connection, up to a bounded timeout per attempt.
TIMEOUT_SECONDS="${SUBCTL_VERIFY_TIMEOUT_SECONDS:-300}"
POLL_INTERVAL_SECONDS="${SUBCTL_VERIFY_POLL_INTERVAL_SECONDS:-15}"
# Every subctl/oc call is bounded: a hung API connection must not eat the whole step.
CMD_TIMEOUT_SECONDS="${SUBCTL_VERIFY_CMD_TIMEOUT_SECONDS:-30}"
# The tunnel can stay in "connecting" forever (NAT discovery never completes while the
# gateway is running, see #3353). Restarting the gateway and route agent pods makes
# them redo the discovery and rebuild the tunnel, so retry that a bounded number of times.
RECOVERY_ATTEMPTS="${SUBCTL_VERIFY_RECOVERY_ATTEMPTS:-2}"
# Worst case per recovery: 3 diagnose x 30s + 4 x (45s delete + 75s rollout) = 570s.
# Whole script worst case: 3 waits x (300s + 75s) + 2 recoveries = ~2265s (~38 min).
DELETE_TIMEOUT_SECONDS="${SUBCTL_VERIFY_DELETE_TIMEOUT_SECONDS:-30}"
ROLLOUT_TIMEOUT_SECONDS="${SUBCTL_VERIFY_ROLLOUT_TIMEOUT_SECONDS:-60}"

wait_for_connections() {
    local deadline=$((SECONDS + TIMEOUT_SECONDS))

    while true; do
        local all_connected=true

        for CLUSTER_NAME in "${CLUSTERS[@]}"; do
            # `subctl show all` exits non-zero while no connection exists yet; tolerate
            # that here so the retry loop is not aborted by `set -e` on the first poll.
            STATUS=$(timeout "$CMD_TIMEOUT_SECONDS" subctl show all --contexts "$CLUSTER_NAME" 2>&1 || true)
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
            return 0
        fi

        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "Submariner connections were not established within ${TIMEOUT_SECONDS}s." >&2
            return 1
        fi

        sleep "$POLL_INTERVAL_SECONDS"
    done
}

# Best-effort: dump what subctl knows, then restart the gateway and route agent pods
# (both are DaemonSets, so they are recreated on the same nodes and keep the gateway label).
recover_submariner() {
    echo "Dumping Submariner diagnostics before restarting the pods..."
    timeout "$CMD_TIMEOUT_SECONDS" subctl diagnose firewall inter-cluster \
        --context "${CLUSTERS[0]}" --remotecontext "${CLUSTERS[1]}" 2>&1 || true
    for CLUSTER_NAME in "${CLUSTERS[@]}"; do
        timeout "$CMD_TIMEOUT_SECONDS" subctl diagnose all --context "$CLUSTER_NAME" 2>&1 || true
    done

    for CLUSTER_NAME in "${CLUSTERS[@]}"; do
        echo "Restarting the Submariner gateway and route agent pods in $CLUSTER_NAME..."
        for APP in submariner-gateway submariner-routeagent; do
            timeout $((DELETE_TIMEOUT_SECONDS + 15)) oc --context "$CLUSTER_NAME" -n submariner-operator delete pod -l "app=$APP" --wait=true --timeout="${DELETE_TIMEOUT_SECONDS}s" || true
            timeout $((ROLLOUT_TIMEOUT_SECONDS + 15)) oc --context "$CLUSTER_NAME" -n submariner-operator rollout status "ds/$APP" --timeout="${ROLLOUT_TIMEOUT_SECONDS}s" || true
        done
    done
}

attempt=0
until wait_for_connections; do
    if [ "$attempt" -ge "$RECOVERY_ATTEMPTS" ]; then
        echo "Submariner is still not connected after $attempt recovery attempt(s)." >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    echo "Recovery attempt $attempt/$RECOVERY_ATTEMPTS: tunnel not established, restarting Submariner pods."
    recover_submariner
done
