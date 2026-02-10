#!/bin/bash
set -euo pipefail

# Create Keycloak external database secret (CI/Test only - for embedded Keycloak)
# Run when using embedded Keycloak with external PostgreSQL

kubectl create secret generic identity-keycloak-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=host="$DB_HOST" \
  --from-literal=user="$DB_KEYCLOAK_USERNAME" \
  --from-literal=password="$DB_KEYCLOAK_PASSWORD" \
  --from-literal=database="$DB_KEYCLOAK_NAME" \
  --from-literal=port="$DB_PORT"
