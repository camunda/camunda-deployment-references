#!/bin/bash

# Create the secret with database credentials for Camunda 8 RDBMS mode.
# Includes Identity and RDBMS secondary storage credentials.
kubectl create secret generic setup-db-secret --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_PORT="$DB_PORT" \
  --from-literal=POSTGRES_ADMIN_USERNAME="$POSTGRES_ADMIN_USERNAME" \
  --from-literal=POSTGRES_ADMIN_PASSWORD="$POSTGRES_ADMIN_PASSWORD" \
  --from-literal=DB_IDENTITY_NAME="$DB_IDENTITY_NAME" \
  --from-literal=DB_IDENTITY_USERNAME="$DB_IDENTITY_USERNAME" \
  --from-literal=DB_IDENTITY_PASSWORD="$DB_IDENTITY_PASSWORD" \
  --from-literal=RDBMS_SECONDARY_DATABASE="$RDBMS_SECONDARY_DATABASE" \
  --from-literal=RDBMS_SECONDARY_USERNAME="$RDBMS_SECONDARY_USERNAME" \
  --from-literal=RDBMS_SECONDARY_PASSWORD="$RDBMS_SECONDARY_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
