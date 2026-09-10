#!/bin/bash

# create a secret to reference external Postgres for each component of Camunda 8
kubectl create secret generic identity-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_IDENTITY_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic webmodeler-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_WEBMODELER_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# RDBMS secondary storage: secret referencing the orchestration database user
kubectl create secret generic orchestration-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_ORCHESTRATION_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
