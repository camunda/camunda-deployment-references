#!/bin/bash
set -euo pipefail

# Script to install Elastic Cloud on Kubernetes (ECK) operator
# Usage: ./02-elasticsearch-install-operator.sh [operator-namespace]

OPERATOR_NAMESPACE=${1:-elastic-system}

echo "Installing ECK (Elastic Cloud on Kubernetes) operator in namespace: $OPERATOR_NAMESPACE"

# Install CRDs first
# TODO(renovate): manage eck manifest version via Renovate (auto-bump)
kubectl apply --server-side -f \
  https://download.elastic.co/downloads/eck/3.1.0/crds.yaml

echo "Waiting for CRDs to be established..."
sleep 10

# Create namespace for the operator
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install the operator
# TODO: renovate
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f \
  https://download.elastic.co/downloads/eck/3.1.0/operator.yaml

echo "Waiting for operator to be ready..."
# Wait for operator pod to be ready (using a more generic approach)
timeout=300
interval=5
end=$((SECONDS+timeout))

echo "Waiting for ECK operator pod to be ready (max 5m)..."
while [ $SECONDS -lt $end ]; do
  if kubectl get pods -n "$OPERATOR_NAMESPACE" -l control-plane=elastic-operator --field-selector=status.phase=Running | grep -q Running; then
    echo "ECK operator is ready."
    break
  fi
  printf "Operator not ready yet...\n"
  sleep $interval
done

if [ $SECONDS -ge $end ]; then
  echo "Timeout reached. Checking operator status:"
  kubectl get pods -n "$OPERATOR_NAMESPACE" -l control-plane=elastic-operator
fi

echo "ECK operator installed successfully!"
