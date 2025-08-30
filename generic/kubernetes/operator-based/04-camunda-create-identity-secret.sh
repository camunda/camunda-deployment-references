#!/bin/bash

# Generate secrets for Camunda Identity components with operator-based configuration
echo "Generating random secrets for Camunda Identity components..."

CONNECTORS_SECRET="$(openssl rand -hex 16)"
export CONNECTORS_SECRET
CONSOLE_SECRET="$(openssl rand -hex 16)"
export CONSOLE_SECRET
OPTIMIZE_SECRET="$(openssl rand -hex 16)"
export OPTIMIZE_SECRET
ORCHESTRATION_SECRET="$(openssl rand -hex 16)"
export ORCHESTRATION_SECRET
ADMIN_PASSWORD="$(openssl rand -hex 16)"
export ADMIN_PASSWORD
USER_PASSWORD="$(openssl rand -hex 16)"
export USER_PASSWORD

echo "Creating Kubernetes secret 'camunda-credentials' with Identity component secrets..."

kubectl create secret generic camunda-credentials \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=identity-connectors-client-token="$CONNECTORS_SECRET" \
  --from-literal=identity-console-client-token="$CONSOLE_SECRET" \
  --from-literal=identity-optimize-client-token="$OPTIMIZE_SECRET" \
  --from-literal=identity-orchestration-client-token="$ORCHESTRATION_SECRET" \
  --from-literal=identity-admin-client-token="$ADMIN_PASSWORD" \
  --from-literal=identity-firstuser-password="$USER_PASSWORD" \
  --from-literal=smtp-password=""

echo "✅ Secret 'camunda-credentials' created successfully in namespace: $CAMUNDA_NAMESPACE"
echo ""
echo "Generated secrets:"
echo "- Connectors client token: $CONNECTORS_SECRET"
echo "- Console client token: $CONSOLE_SECRET"
echo "- Optimize client token: $OPTIMIZE_SECRET"
echo "- Orchestration client token: $ORCHESTRATION_SECRET"
echo "- Admin password: $ADMIN_PASSWORD"
echo "- First user password: $USER_PASSWORD"
echo ""
echo "💡 Save these credentials in a secure location for future reference."
