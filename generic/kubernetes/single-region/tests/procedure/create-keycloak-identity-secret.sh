#!/bin/bash

# Create Keycloak identity secret for Camunda components
# Used by the operator-based test workflow

PUSHER_APP_SECRET="$(openssl rand -hex 16)"
PUSHER_APP_KEY="$(openssl rand -hex 16)"

kubectl create secret generic identity-secret-for-components \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=identity-connectors-client-token="$CONNECTORS_SECRET" \
  --from-literal=identity-console-client-token="$CONSOLE_SECRET" \
  --from-literal=identity-webmodeler-client-token="$WEB_MODELER_SECRET" \
  --from-literal=identity-orchestration-client-token="$ORCHESTRATION_SECRET" \
  --from-literal=identity-optimize-client-token="$OPTIMIZE_SECRET" \
  --from-literal=identity-admin-client-token="$ADMIN_PASSWORD" \
  --from-literal=identity-first-user-password="$FIRST_USER_PASSWORD" \
  --from-literal=webmodeler-pusher-app-secret="$PUSHER_APP_SECRET" \
  --from-literal=webmodeler-pusher-app-key="$PUSHER_APP_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
