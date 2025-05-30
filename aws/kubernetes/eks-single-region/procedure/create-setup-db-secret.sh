#!/bin/bash

kubectl create secret generic setup-db-secret --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=AURORA_ENDPOINT="$AURORA_ENDPOINT" \
  --from-literal=AURORA_PORT="$AURORA_PORT" \
  --from-literal=AURORA_USERNAME="$AURORA_USERNAME" \
  --from-literal=AURORA_PASSWORD="$AURORA_PASSWORD" \
  --from-literal=DB_KEYCLOAK_NAME="$DB_KEYCLOAK_NAME" \
  --from-literal=DB_KEYCLOAK_USERNAME="$DB_KEYCLOAK_USERNAME" \
  --from-literal=DB_KEYCLOAK_PASSWORD="$DB_KEYCLOAK_PASSWORD" \
  --from-literal=DB_IDENTITY_NAME="$DB_IDENTITY_NAME" \
  --from-literal=DB_IDENTITY_USERNAME="$DB_IDENTITY_USERNAME" \
  --from-literal=DB_IDENTITY_PASSWORD="$DB_IDENTITY_PASSWORD" \
  --from-literal=DB_WEBMODELER_NAME="$DB_WEBMODELER_NAME" \
  --from-literal=DB_WEBMODELER_USERNAME="$DB_WEBMODELER_USERNAME" \
  --from-literal=DB_WEBMODELER_PASSWORD="$DB_WEBMODELER_PASSWORD"
