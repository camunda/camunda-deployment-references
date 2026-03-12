#!/bin/bash
set -euo pipefail

# Create camunda-credentials with randomly generated credentials for Bitnami-based deployments.
# This includes both Identity client tokens AND database passwords required by the
# Bitnami PostgreSQL sub-charts (identityKeycloak, identityPostgresql, webModelerPostgresql).
#
# The chart defaults set existingSecret: camunda-credentials for all PostgreSQL instances,
# so the secret must contain all database password keys upfront.
#
# Must run BEFORE helm install.

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"

echo "🔐 Creating camunda-credentials in namespace '$NAMESPACE'..."

# Identity client tokens
CONNECTORS_SECRET="$(openssl rand -hex 16)"
CONSOLE_SECRET="$(openssl rand -hex 16)"
WEB_MODELER_SECRET="$(openssl rand -hex 16)"
ORCHESTRATION_SECRET="$(openssl rand -hex 16)"
OPTIMIZE_SECRET="$(openssl rand -hex 16)"
ADMIN_PASSWORD="$(openssl rand -hex 16)"
FIRST_USER_PASSWORD="$(openssl rand -hex 16)"

# Database passwords for Bitnami PostgreSQL sub-charts
KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -hex 16)"
KEYCLOAK_PG_ADMIN_PASSWORD="$(openssl rand -hex 16)"
KEYCLOAK_PG_USER_PASSWORD="$(openssl rand -hex 16)"
IDENTITY_PG_ADMIN_PASSWORD="$(openssl rand -hex 16)"
IDENTITY_PG_USER_PASSWORD="$(openssl rand -hex 16)"
WEBMODELER_PG_ADMIN_PASSWORD="$(openssl rand -hex 16)"
WEBMODELER_PG_USER_PASSWORD="$(openssl rand -hex 16)"

kubectl create secret generic camunda-credentials \
    --namespace "$NAMESPACE" \
    --from-literal=identity-connectors-client-token="$CONNECTORS_SECRET" \
    --from-literal=identity-console-client-token="$CONSOLE_SECRET" \
    --from-literal=identity-webmodeler-client-token="$WEB_MODELER_SECRET" \
    --from-literal=identity-orchestration-client-token="$ORCHESTRATION_SECRET" \
    --from-literal=identity-optimize-client-token="$OPTIMIZE_SECRET" \
    --from-literal=identity-admin-client-token="$ADMIN_PASSWORD" \
    --from-literal=identity-first-user-password="$FIRST_USER_PASSWORD" \
    --from-literal=identity-keycloak-admin-password="$KEYCLOAK_ADMIN_PASSWORD" \
    --from-literal=identity-keycloak-postgresql-admin-password="$KEYCLOAK_PG_ADMIN_PASSWORD" \
    --from-literal=identity-keycloak-postgresql-user-password="$KEYCLOAK_PG_USER_PASSWORD" \
    --from-literal=identity-postgresql-admin-password="$IDENTITY_PG_ADMIN_PASSWORD" \
    --from-literal=identity-postgresql-user-password="$IDENTITY_PG_USER_PASSWORD" \
    --from-literal=web-modeler-postgresql-admin-password="$WEBMODELER_PG_ADMIN_PASSWORD" \
    --from-literal=web-modeler-postgresql-user-password="$WEBMODELER_PG_USER_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ camunda-credentials created"
