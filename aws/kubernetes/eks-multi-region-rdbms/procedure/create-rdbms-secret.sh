#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Creates the Kubernetes secret holding the RDBMS password in every active
# cluster. Referenced from the Helm values as
# `orchestration.data.secondaryStorage.rdbms.secret.existingSecret`.
#
# The password never appears in a values file: only the JDBC URL and the
# username are templated.

: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RDBMS_PASSWORD:?CAMUNDA_RDBMS_PASSWORD must be set, e.g. from 'terraform output -raw database_password'}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-management-api.sh"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

mapfile -t slots < <(camunda::target_slots "$@")

for i in "${slots[@]}"; do
    context="${contexts[$i]}"
    echo "Creating secret camunda-rdbms-secret in $context/$CAMUNDA_NAMESPACE"
    printf '%s' "$CAMUNDA_RDBMS_PASSWORD" | kubectl --context "$context" create secret generic camunda-rdbms-secret \
        --namespace "$CAMUNDA_NAMESPACE" \
        --from-file=password=/dev/stdin \
        --dry-run=client -o yaml | kubectl --context "$context" apply -f -
done
