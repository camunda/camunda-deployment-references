#!/bin/bash

# Create secrets to reference external Postgres for each component of Camunda 8 (RDBMS mode)
# This variant creates the Identity secret and the RDBMS secondary storage secret.
# WebModeler is not included as it is disabled in RDBMS mode.

kubectl create secret generic identity-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_IDENTITY_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Secret for RDBMS secondary storage password (referenced by values-rdbms.yml)
kubectl create secret generic rdbms-secondary-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$RDBMS_SECONDARY_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
