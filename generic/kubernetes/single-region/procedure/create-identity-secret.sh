#!/bin/bash

kubectl create secret generic identity-secret-for-components \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=identity-connectors-client-token="$CONNECTORS_SECRET" \
  --from-literal=identity-console-client-token="$CONSOLE_SECRET" \
  --from-literal=identity-orchestration-client-token="$ORCHESTRATION_SECRET" \
  --from-literal=identity-optimize-client-token="$OPTIMIZE_SECRET" \
  --from-literal=identity-admin-password="$ADMIN_PASSWORD" \
  --from-literal=identity-first-user-password="$FIRST_USER_PASSWORD" \
  --from-literal=smtp-password=""
