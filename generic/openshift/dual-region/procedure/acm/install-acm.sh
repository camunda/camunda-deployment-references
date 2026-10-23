#!/bin/bash
set -euo pipefail

# OLM cannot resolve the Subscription until the redhat-operators catalog is READY
# (it may lag on a freshly created cluster), so wait up to 5 minutes for it.
for _ in $(seq 1 60); do
    CATALOG_STATE=$(oc --context "$CLUSTER_0" --namespace openshift-marketplace get catalogsource redhat-operators \
        -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null || true)
    echo "redhat-operators catalog state: ${CATALOG_STATE:-unknown}"
    [ "$CATALOG_STATE" = "READY" ] && break
    sleep 5
done

if [ "$CATALOG_STATE" != "READY" ]; then
    echo "redhat-operators catalog is not READY after 5 minutes." >&2
    exit 1
fi

oc --context "$CLUSTER_0" apply -f install-manifest.yml
