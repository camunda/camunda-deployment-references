#!/bin/bash
# postgresql/set-secrets.sh - Create PostgreSQL secrets for CloudNativePG clusters

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}

# Function to create or get secret
create_or_get_secret() {
    local secret_name=$1
    local username=$2
    local password_var_name=$3

    if kubectl get secret "$secret_name" -n "$CAMUNDA_NAMESPACE" >/dev/null 2>&1; then
        echo "Secret $secret_name already exists - retrieving password"
        local existing_password
        existing_password=$(kubectl get secret "$secret_name" -n "$CAMUNDA_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
        eval "$password_var_name=\"$existing_password\""
    else
        echo "Creating new secret $secret_name"
        local new_password
        new_password=$(openssl rand -base64 18)
        kubectl create secret generic "$secret_name" -n "$CAMUNDA_NAMESPACE" \
          --from-literal=username="$username" \
          --from-literal=password="$new_password" \
          --dry-run=client -o yaml | kubectl apply -f -
        eval "$password_var_name=\"$new_password\""
    fi
}

echo "Creating PostgreSQL secrets in namespace: $CAMUNDA_NAMESPACE"

# Identity superuser (username=root) and bootstrap (username=identity)
create_or_get_secret "pg-identity-superuser-secret" "root" "IDENTITY_SUPER_PASS"
create_or_get_secret "pg-identity-secret" "identity" "IDENTITY_BOOT_PASS"

# Keycloak superuser (username=root) and bootstrap (username=keycloak)
create_or_get_secret "pg-keycloak-superuser-secret" "root" "KEYCLOAK_SUPER_PASS"
create_or_get_secret "pg-keycloak-secret" "keycloak" "KEYCLOAK_BOOT_PASS"

# Webmodeler superuser (username=root) and bootstrap (username=webmodeler)
create_or_get_secret "pg-webmodeler-superuser-secret" "root" "WEBM_SUPER_PASS"
create_or_get_secret "pg-webmodeler-secret" "webmodeler" "WEBM_BOOT_PASS"

echo "PostgreSQL secrets created successfully!"
