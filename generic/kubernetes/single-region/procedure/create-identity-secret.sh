#!/bin/bash

kubectl create secret generic identity-secret-for-components \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=connectors-secret="$CONNECTORS_SECRET" \
  --from-literal=console-secret="$CONSOLE_SECRET" \
  --from-literal=orchestration-secret="$ORCHESTRATION_SECRET" \
  --from-literal=optimize-secret="$OPTIMIZE_SECRET" \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --from-literal=first-user-password="$FIRST_USER_PASSWORD" \
  --from-literal=smtp-password=""
