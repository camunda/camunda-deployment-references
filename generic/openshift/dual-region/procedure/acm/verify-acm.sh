#!/bin/bash
set -euo pipefail

# Wait up to 6 minutes. If no CSV appears after 3 minutes, OLM probably did not
# resolve the Subscription: recreate it once to force a new resolution.
MAX_ATTEMPTS=72
RETRY_AT=36

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    STATUS=$(oc --context "$CLUSTER_0" --namespace open-cluster-management get csv 2>&1 || true)
    echo "$STATUS"

    if echo "$STATUS" | grep -q "Succeeded"; then
        echo "CSV is Succeeded!"
        exit 0
    fi

    if [ "$attempt" -eq "$RETRY_AT" ] && echo "$STATUS" | grep -q "No resources found"; then
        echo "No CSV after 3 minutes, recreating the Subscription."
        oc --context "$CLUSTER_0" --namespace open-cluster-management delete subscription advanced-cluster-management
        oc --context "$CLUSTER_0" apply -f install-manifest.yml
    fi

    sleep 5
done

echo "ACM CSV did not reach Succeeded in time. Diagnostics:" >&2
oc --context "$CLUSTER_0" --namespace open-cluster-management get subscription advanced-cluster-management -o yaml || true
oc --context "$CLUSTER_0" --namespace open-cluster-management get installplan,csv || true
oc --context "$CLUSTER_0" --namespace openshift-marketplace get catalogsource redhat-operators -o yaml || true
oc --context "$CLUSTER_0" --namespace openshift-marketplace get pods || true
exit 1

# Example output:
# NAME                                  DISPLAY                                      VERSION   REPLACES                              PHASE
# advanced-cluster-management.v2.13.2   Advanced Cluster Management for Kubernetes   2.13.2    advanced-cluster-management.v2.13.2   Succeeded
