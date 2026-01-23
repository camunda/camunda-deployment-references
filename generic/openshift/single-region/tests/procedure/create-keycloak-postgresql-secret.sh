#!/bin/bash
set -euo pipefail

# Create a dedicated secret for Keycloak embedded PostgreSQL (CI/Test only)
#
# This secret is separate from identity-secret-for-components and contains
# only the PostgreSQL credentials for the embedded Keycloak database.
#
# Required environment variables:
#   - CAMUNDA_NAMESPACE: Kubernetes namespace
#   - KEYCLOAK_PSQL_ADMIN_PASSWORD: PostgreSQL admin password
#   - KEYCLOAK_PSQL_USER_PASSWORD: PostgreSQL user password
#
# The secret keys match the Camunda Helm chart expectations:
#   - identity-keycloak-postgresql-admin-password
#   - identity-keycloak-postgresql-user-password

kubectl create secret generic identity-keycloak-postgresql-secret \
    --namespace "$CAMUNDA_NAMESPACE" \
    --from-literal=identity-keycloak-postgresql-admin-password="$KEYCLOAK_PSQL_ADMIN_PASSWORD" \
    --from-literal=identity-keycloak-postgresql-user-password="$KEYCLOAK_PSQL_USER_PASSWORD"
