#!/bin/bash
set -euo pipefail

# Copy the OpenShift service CA bundle into a Secret in the Camunda namespace
# so the chart can trust the service-serving certificate of the orchestration
# gRPC server through `global.tls.caBundle.secret.existingSecret`.
#
# Required env:
#   CAMUNDA_NAMESPACE                target namespace (e.g. "camunda")
#   CAMUNDA_PLATFORM_SERVICE_CA_SECRET  destination secret name
#                                       (default: camunda-platform-service-ca)

: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE is required}"
DEST_SECRET="${CAMUNDA_PLATFORM_SERVICE_CA_SECRET:-camunda-platform-service-ca}"

SERVICE_CA="$(oc -n "$CAMUNDA_NAMESPACE" get configmap openshift-service-ca.crt \
    -o go-template='{{index .data "service-ca.crt"}}')"

if [[ -z "$SERVICE_CA" ]]; then
    echo "❌ configmap openshift-service-ca.crt in $CAMUNDA_NAMESPACE has no service-ca.crt key." >&2
    exit 1
fi

echo "ℹ️  Creating secret $CAMUNDA_NAMESPACE/$DEST_SECRET from configmap openshift-service-ca.crt"

oc -n "$CAMUNDA_NAMESPACE" create secret generic "$DEST_SECRET" \
    --from-literal=ca.crt="$SERVICE_CA" \
    --dry-run=client -o yaml \
    | oc apply -f -
