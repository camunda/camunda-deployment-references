#!/bin/bash
set -euo pipefail

# Creates the Camunda namespace in every active cluster.
#
# Unlike the dual-region reference architecture, a single namespace name is
# reused in every cluster: Submariner Lighthouse disambiguates identically
# named services with the exporting cluster ID, so `<clusterID>.<service>.<ns>.
# svc.clusterset.local` stays unambiguous. This keeps the number of namespaces
# linear instead of quadratic in the number of regions.

: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    echo "Creating namespace $CAMUNDA_NAMESPACE in $context"
    kubectl --context "$context" create namespace "$CAMUNDA_NAMESPACE" \
        --dry-run=client -o yaml | kubectl --context "$context" apply -f -
done
