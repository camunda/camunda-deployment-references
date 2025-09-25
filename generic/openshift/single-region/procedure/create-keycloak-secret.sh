#!/bin/bash

# create a secret to reference database credentials if you use embedded KeyCloak with postgresql
kubectl create secret generic identity-keycloak-psql-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=admin-password-key="$KEYCLOAK_PSQL_ADMIN_PASSWORD" \
  --from-literal=user-password-key="$KEYCLOAK_PSQL_USER_PASSWORD" \
