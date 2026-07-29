#!/bin/bash
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

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    echo "Creating secret camunda-rdbms-secret in $context/$CAMUNDA_NAMESPACE"
    kubectl --context "$context" create secret generic camunda-rdbms-secret \
        --namespace "$CAMUNDA_NAMESPACE" \
        --from-literal=password="$CAMUNDA_RDBMS_PASSWORD" \
        --dry-run=client -o yaml | kubectl --context "$context" apply -f -
done
