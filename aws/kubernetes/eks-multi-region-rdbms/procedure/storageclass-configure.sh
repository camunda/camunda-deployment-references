#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# EKS ships gp2 as the default StorageClass. Zeebe writes its Raft log and
# snapshots to this volume, so gp3 with a guaranteed IOPS floor is used instead.
# Applied to every active cluster.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/lib-management-api.sh"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

mapfile -t slots < <(camunda::target_slots "$@")

for i in "${slots[@]}"; do
    context="${contexts[$i]}"

    echo "Configuring the default StorageClass on $context"
    kubectl --context "$context" patch storageclass gp2 \
        -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
    kubectl --context "$context" apply -f "$SCRIPT_DIR/manifests/storage-class.yml"
done
