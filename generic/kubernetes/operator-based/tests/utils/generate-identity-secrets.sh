#!/bin/bash
set -euo pipefail

# Generate secrets for Camunda Identity components with operator-based configuration
NAMESPACE=${1:-${CAMUNDA_NAMESPACE:-camunda}}

echo "Creating Camunda Identity secrets in namespace: $NAMESPACE"

# Function to create or get secret field
create_or_get_secret_field() {
    local secret_name=$1
    local field_name=$2
    local var_name=$3
    local default_value=${4:-$(openssl rand -hex 16)}

    if kubectl get secret "$secret_name" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "Secret $secret_name already exists - retrieving $field_name"
        local existing_value
        existing_value=$(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath="{.data.$field_name}" | base64 -d 2>/dev/null || echo "")
        if [ -n "$existing_value" ]; then
            eval "$var_name=\"$existing_value\""
        else
            echo "Field $field_name not found in existing secret, using default value"
            eval "$var_name=\"$default_value\""
        fi
    else
        echo "Secret $secret_name does not exist, will create with new $field_name"
        eval "$var_name=\"$default_value\""
    fi
}

# Check if the secret exists
SECRET_EXISTS=false
if kubectl get secret camunda-credentials -n "$NAMESPACE" >/dev/null 2>&1; then
    SECRET_EXISTS=true
    echo "✅ Secret 'camunda-credentials' already exists in namespace: $NAMESPACE"
else
    echo "Generating new 'camunda-credentials' secret in namespace: $NAMESPACE"
fi

# Generate or retrieve all secret fields
create_or_get_secret_field "camunda-credentials" "identity-connectors-client-token" "CONNECTORS_SECRET"
create_or_get_secret_field "camunda-credentials" "identity-console-client-token" "CONSOLE_SECRET"
create_or_get_secret_field "camunda-credentials" "identity-optimize-client-token" "OPTIMIZE_SECRET"
create_or_get_secret_field "camunda-credentials" "identity-orchestration-client-token" "ORCHESTRATION_SECRET"
create_or_get_secret_field "camunda-credentials" "identity-webmodeler-client-token" "WEBMODELER_SECRET"
create_or_get_secret_field "camunda-credentials" "identity-admin-client-token" "IDENTITY_SECRET"
create_or_get_secret_field "camunda-credentials" "identity-firstuser-password" "USER_PASSWORD"
create_or_get_secret_field "camunda-credentials" "smtp-password" "SMTP_PASSWORD" ""

# Create or update the secret
if [ "$SECRET_EXISTS" = false ]; then
    echo "Creating Kubernetes secret 'camunda-credentials' with Identity component secrets..."

    kubectl create secret generic camunda-credentials \
      --namespace "$NAMESPACE" \
      --from-literal=identity-connectors-client-token="$CONNECTORS_SECRET" \
      --from-literal=identity-console-client-token="$CONSOLE_SECRET" \
      --from-literal=identity-optimize-client-token="$OPTIMIZE_SECRET" \
      --from-literal=identity-orchestration-client-token="$ORCHESTRATION_SECRET" \
      --from-literal=identity-webmodeler-client-token="$WEBMODELER_SECRET" \
      --from-literal=identity-admin-client-token="$IDENTITY_SECRET" \
      --from-literal=identity-firstuser-password="$USER_PASSWORD" \
      --from-literal=smtp-password="$SMTP_PASSWORD"

    echo "✅ Secret 'camunda-credentials' created successfully in namespace: $NAMESPACE"
fi
