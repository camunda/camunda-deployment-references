#!/bin/bash

oc create secret generic identity-secret-for-components \
  --namespace camunda \
  --from-literal=identity-connectors-client-token="$CONNECTORS_SECRET" \
  --from-literal=identity-console-client-token="$CONSOLE_SECRET" \
  --from-literal=identity-core-client-token="$CORE_SECRET" \
  --from-literal=identity-optimize-client-token="$OPTIMIZE_SECRET" \
  --from-literal=identity-keycloak-admin-password="$ADMIN_PASSWORD" \
  --from-literal=identity-firstuser-password="$FIRST_USER_PASSWORD" \
  --from-literal=identity-keycloak-postgresql-user-password="$KEYCLOAK_PG_USER_PASSWORD" \
  --from-literal=identity-keycloak-postgresql-admin-password="$KEYCLOAK_PG_ADMIN_PASSWORD" \
  --from-literal=smtp-password=""
