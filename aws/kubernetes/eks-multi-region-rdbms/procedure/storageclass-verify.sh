#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Asserts that ebs-sc is the one and only default StorageClass in every active
# cluster. A second default makes PVC binding non-deterministic.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

SC_NAME="ebs-sc"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-management-api.sh"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

failed=0
mapfile -t slots < <(camunda::target_slots "$@")

for i in "${slots[@]}"; do
    context="${contexts[$i]}"

    defaults="$(kubectl --context "$context" get storageclass -o json |
        jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class"=="true") | .metadata.name')"

    if [ "$defaults" = "$SC_NAME" ]; then
        echo "OK: $context has '$SC_NAME' as its only default StorageClass."
    else
        echo "FAIL: $context default StorageClass(es): ${defaults:-<none>}" >&2
        failed=1
    fi
done

exit "$failed"
