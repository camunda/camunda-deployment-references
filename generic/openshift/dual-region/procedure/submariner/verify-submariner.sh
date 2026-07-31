#!/bin/bash
set -euo pipefail

# The Submariner addons take a while to reconcile after install-submariner.sh
# applies the manifests. Poll until every addon reports Available=True,
# Degraded=False and no longer Progressing, up to a bounded timeout — an
# unbounded loop here would silently consume the caller's whole step budget and
# fail with an opaque timeout instead of showing the last observed addon status.
TIMEOUT_SECONDS="${SUBMARINER_ADDON_TIMEOUT_SECONDS:-600}"
POLL_INTERVAL_SECONDS="${SUBMARINER_ADDON_POLL_INTERVAL_SECONDS:-5}"
deadline=$((SECONDS + TIMEOUT_SECONDS))

while true; do
    oc_output=$(oc --context "$CLUSTER_0" get managedclusteraddon -A)
    STATUS=$(echo "$oc_output" | grep 'submariner' || true)
    # display the status
    oc --context "$CLUSTER_0" -n "oc-clusters-broker" describe Broker
    echo "$oc_output" | grep -E 'NAME|submariner' || true

    if [ -z "$STATUS" ]; then
        echo "No submariner addons found yet, waiting..."
    elif echo "$STATUS" | awk '{if ($3=="True" && $4=="False" && $5=="") next; else exit 1}'; then
        echo "All submariner addons are Available=True, Degraded=False, and not Progressing!"
        exit 0
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "Submariner addons did not become ready within ${TIMEOUT_SECONDS}s." >&2
        echo "Last observed status:" >&2
        echo "${STATUS:-<no submariner addon found>}" >&2
        exit 1
    fi

    sleep "$POLL_INTERVAL_SECONDS"
done

# Example output:
# NAMESPACE          NAME                          AVAILABLE   DEGRADED   PROGRESSING
# cluster-region-2   submariner                    True                   False
# local-cluster      submariner                    True                   False
