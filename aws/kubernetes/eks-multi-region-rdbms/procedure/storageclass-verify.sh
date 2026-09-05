#!/bin/bash
set -euo pipefail

# Asserts that ebs-sc is the one and only default StorageClass in every active
# cluster. A second default makes PVC binding non-deterministic.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

SC_NAME="ebs-sc"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

failed=0
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
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
