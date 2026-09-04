#!/bin/bash
set -euo pipefail

# Simulates the loss of one region by removing everything Camunda from it.
#
#   ./simulate-region-loss.sh <slot>
#
# This is a TEST helper, not an operational procedure. A real region loss is
# abrupt: the API server becomes unreachable and nothing can be uninstalled
# cleanly. Removing the workload is the closest reproducible approximation and
# is what the dual-region suite does as well.
#
# It deliberately does NOT tear down the EKS cluster or the Transit Gateway
# attachments: recreating them would take 25 minutes and would test Terraform
# rather than the Camunda failure behaviour.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

if [ $# -ne 1 ]; then
    echo "usage: $0 <region-slot>" >&2
    exit 1
fi

SLOT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib-management-api.sh
. "$SCRIPT_DIR/lib-management-api.sh"
camunda::require_slot "$SLOT" "the region-loss slot"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
context="${contexts[$SLOT]}"

echo "Simulating the loss of region slot $SLOT ($context)"

helm --kube-context "$context" --namespace "$CAMUNDA_NAMESPACE" \
    uninstall "$CAMUNDA_RELEASE_NAME" --wait --timeout 10m

# The PVCs must go too: a region that comes back reuses its node IDs but must
# rebuild its Raft state from the surviving replicas, which is what a genuinely
# lost region would do.
kubectl --context "$context" --namespace "$CAMUNDA_NAMESPACE" \
    delete pvc --all --ignore-not-found --wait=true --timeout=5m

echo "Region slot $SLOT no longer runs Camunda."
