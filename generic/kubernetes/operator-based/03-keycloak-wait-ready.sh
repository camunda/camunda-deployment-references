#!/bin/bash
set -euo pipefail

# Script to wait for Keycloak instance to become ready
# Usage: ./03-keycloak-wait-ready.sh [namespace] [instance-name]

NAMESPACE=${1:-$CAMUNDA_NAMESPACE}
INSTANCE_NAME=${2:-keycloak}

echo "Waiting for Keycloak instance '$INSTANCE_NAME' in namespace: $NAMESPACE"

# Wait up to 5 minutes for the Keycloak CR to become Ready
echo "Waiting for Keycloak (max 5m) to become Ready..."
timeout=300
interval=5
end=$((SECONDS+timeout))

while [ $SECONDS -lt $end ]; do
  ready=$(kubectl get keycloak "$INSTANCE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [ "$ready" = "True" ]; then
    echo "Keycloak is Ready."
    break
  fi
  printf "Ready=%s ...\n" "${ready:-unknown}"
  sleep $interval
done

if [ $SECONDS -ge $end ]; then
  echo "Timeout reached. Current instance state:"
fi

kubectl get keycloak "$INSTANCE_NAME" -n "$NAMESPACE" -o wide || true
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak,app.kubernetes.io/instance="$INSTANCE_NAME" || true
kubectl get svc -n "$NAMESPACE" | grep keycloak || true
