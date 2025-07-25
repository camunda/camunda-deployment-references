#!/bin/bash

# Create the secret with all database credentials
kubectl create secret generic setup-db-secret --namespace camunda \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_PORT="$DB_PORT" \
  --from-literal=POSTGRES_ADMIN_USERNAME="$POSTGRES_ADMIN_USERNAME" \
  --from-literal=POSTGRES_ADMIN_PASSWORD="$POSTGRES_ADMIN_PASSWORD" \
  --from-literal=DB_KEYCLOAK_NAME="$DB_KEYCLOAK_NAME" \
  --from-literal=DB_KEYCLOAK_USERNAME="$DB_KEYCLOAK_USERNAME" \
  --from-literal=DB_KEYCLOAK_PASSWORD="$DB_KEYCLOAK_PASSWORD" \
  --from-literal=DB_IDENTITY_NAME="$DB_IDENTITY_NAME" \
  --from-literal=DB_IDENTITY_USERNAME="$DB_IDENTITY_USERNAME" \
  --from-literal=DB_IDENTITY_PASSWORD="$DB_IDENTITY_PASSWORD" \
  --from-literal=DB_WEBMODELER_NAME="$DB_WEBMODELER_NAME" \
  --from-literal=DB_WEBMODELER_USERNAME="$DB_WEBMODELER_USERNAME" \
  --from-literal=DB_WEBMODELER_PASSWORD="$DB_WEBMODELER_PASSWORD"
