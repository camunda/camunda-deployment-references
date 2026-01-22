#!/bin/bash

# Create a secret to reference external database credentials for Keycloak
# This script should only be run when Keycloak is enabled (not when using external OIDC)

kubectl create secret generic identity-keycloak-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=host="$DB_HOST" \
  --from-literal=user="$DB_KEYCLOAK_USERNAME" \
  --from-literal=password="$DB_KEYCLOAK_PASSWORD" \
  --from-literal=database="$DB_KEYCLOAK_NAME" \
  --from-literal=port=5432
