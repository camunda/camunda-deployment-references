#!/bin/bash
set -euo pipefail

# Create secrets to reference external Postgres for each component of Camunda 8 (RDBMS variant)
# Includes orchestration DB secret for RDBMS secondary storage

kubectl create secret generic identity-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_IDENTITY_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic webmodeler-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_WEBMODELER_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic orchestration-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_ORCHESTRATION_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
