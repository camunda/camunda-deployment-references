#!/bin/bash

oc create secret generic identity-secret-for-components \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=identity-connectors-client-token="$CONNECTORS_SECRET" \
  --from-literal=identity-console-client-token="$CONSOLE_SECRET" \
  --from-literal=identity-webmodeler-client-token="$WEB_MODELER_SECRET" \
  --from-literal=identity-orchestration-client-token="$ORCHESTRATION_SECRET" \
  --from-literal=identity-optimize-client-token="$OPTIMIZE_SECRET" \
  --from-literal=identity-admin-client-token="$ADMIN_PASSWORD" \
  --from-literal=identity-first-user-password="$FIRST_USER_PASSWORD" \
  --from-literal=identity-keycloak-pg-admin-password-key="$KEYCLOAK_PSQL_ADMIN_PASSWORD"  \
  --from-literal=identity-keycloak-pg-user-password-key="$KEYCLOAK_PSQL_USER_PASSWORD"  \
  --from-literal=smtp-password=""
