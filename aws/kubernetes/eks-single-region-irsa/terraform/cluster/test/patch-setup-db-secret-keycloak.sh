#!/bin/bash

# Create Keycloak database secret for IRSA (CI/Test only - for embedded Keycloak)
# This script adds the Keycloak DB secret to an existing setup-db-secret
# Run after create-setup-db-secret.sh when using embedded Keycloak

kubectl patch secret setup-db-secret --namespace "$CAMUNDA_NAMESPACE" --type='json' -p='[
  {"op": "add", "path": "/data/DB_KEYCLOAK_NAME", "value": "'"$(echo -n "$DB_KEYCLOAK_NAME" | base64)"'"},
  {"op": "add", "path": "/data/DB_KEYCLOAK_USERNAME", "value": "'"$(echo -n "$DB_KEYCLOAK_USERNAME" | base64)"'"}
]'
