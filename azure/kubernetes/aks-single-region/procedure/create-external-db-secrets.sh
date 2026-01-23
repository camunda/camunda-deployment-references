#!/bin/bash

# Create secrets to reference external Postgres for each component of Camunda 8
# Note: If using embedded Keycloak, also run test/create-keycloak-db-secret.sh

kubectl create secret generic identity-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_IDENTITY_PASSWORD"

kubectl create secret generic webmodeler-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="$DB_WEBMODELER_PASSWORD"
