#!/bin/bash
# postgresql/deploy.sh - Deploy PostgreSQL via CloudNativePG operator

set -euo pipefail

# Variables
NAMESPACE=${NAMESPACE:-camunda}
OPERATOR_NAMESPACE=${1:-cnpg-system}

# TODO: renovate

# Install CloudNativePG operator CRDs and operator
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f \
      "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml"

# Wait for operator to be ready
kubectl rollout status deployment \
  -n "$OPERATOR_NAMESPACE" cnpg-controller-manager
echo "CloudNativePG operator deployed in namespace: $OPERATOR_NAMESPACE"

# Create PostgreSQL secrets
NAMESPACE="$NAMESPACE" "./set-secrets.sh"

# Deploy PostgreSQL
kubectl apply --server-side -f "postgresql-clusters.yml" -n "$NAMESPACE"

# Wait for PostgreSQL cluster to be ready
kubectl wait --for=condition=Ready --timeout=600s cluster --all -n "$NAMESPACE"

echo "PostgreSQL deployment completed in namespace: $NAMESPACE"
