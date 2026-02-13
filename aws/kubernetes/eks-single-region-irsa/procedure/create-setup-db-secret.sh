#!/bin/bash

# Create secret for database setup

kubectl create secret generic setup-db-secret --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=AURORA_ENDPOINT="$AURORA_ENDPOINT" \
  --from-literal=AURORA_PORT="$AURORA_PORT" \
  --from-literal=AURORA_USERNAME="$AURORA_USERNAME" \
  --from-literal=AURORA_PASSWORD="$AURORA_PASSWORD" \
  --from-literal=DB_IDENTITY_NAME="$DB_IDENTITY_NAME" \
  --from-literal=DB_IDENTITY_USERNAME="$DB_IDENTITY_USERNAME" \
  --from-literal=DB_WEBMODELER_NAME="$DB_WEBMODELER_NAME" \
  --from-literal=DB_WEBMODELER_USERNAME="$DB_WEBMODELER_USERNAME" \
  --dry-run=client -o yaml | kubectl apply -f -
