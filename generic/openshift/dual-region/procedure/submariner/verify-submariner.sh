#!/bin/bash
set -euo pipefail

# The Submariner addons take a while to reconcile after install-submariner.sh
# applies the manifests. Poll until every addon reports Available=True with no
# non-False status column after it, up to a bounded timeout — an unbounded loop
# here would silently consume the caller's whole step budget and fail with an
# opaque timeout instead of showing the last observed addon status.
#
# Note on the awk check below: `oc get managedclusteraddon` leaves DEGRADED
# blank when the addon is not degraded, and awk collapses whitespace, so the
# field after AVAILABLE is whichever of DEGRADED/PROGRESSING is populated. The
# condition therefore reads "AVAILABLE is True, the one populated status column
# after it is False, and there is no further column".
TIMEOUT_SECONDS="${SUBMARINER_ADDON_TIMEOUT_SECONDS:-600}"
POLL_INTERVAL_SECONDS="${SUBMARINER_ADDON_POLL_INTERVAL_SECONDS:-5}"
deadline=$((SECONDS + TIMEOUT_SECONDS))

# Support both the 0-indexed (CLUSTER_0) and 1-indexed (CLUSTER_1_NAME)
# cluster-context naming conventions, as diagnose-submariner.sh does. Without
# this, `set -u` aborts the script on the first `oc` call on every branch that
# uses the 1-indexed names, before a single addon has been polled.
HUB_CONTEXT="${CLUSTER_0:-${CLUSTER_1_NAME:-}}"
if [ -z "$HUB_CONTEXT" ]; then
    echo "Neither CLUSTER_0 nor CLUSTER_1_NAME is set; cannot reach the hub cluster." >&2
    exit 1
fi

while true; do
    # Both calls are best-effort: this script polls while the addons are still
    # being reconciled, so the resources may not exist yet and the API may answer
    # transiently. Before this file gained `set -e` they could fail freely; keep
    # that tolerance rather than aborting the whole wait.
    oc_output=$(oc --context "$HUB_CONTEXT" get managedclusteraddon -A || true)
    STATUS=$(echo "$oc_output" | grep 'submariner' || true)
    # display the status
    oc --context "$HUB_CONTEXT" -n "oc-clusters-broker" describe Broker || true
    echo "$oc_output" | grep -E 'NAME|submariner' || true

    if [ -z "$STATUS" ]; then
        echo "No submariner addons found yet, waiting..."
    elif echo "$STATUS" | awk '{if ($3=="True" && $4=="False" && $5=="") next; else exit 1}'; then
        echo "All submariner addons are Available=True and not Degraded/Progressing!"
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
