#!/bin/bash
# postgresql/set-secrets.sh - Create PostgreSQL secrets for CloudNativePG clusters
#
# Environment variables:
#   CAMUNDA_NAMESPACE  - Target namespace (default: camunda)
#   CLUSTER_FILTER     - Optional: only create secrets for specific clusters, comma-separated

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
CLUSTER_FILTER=${CLUSTER_FILTER:-}

# Check if secrets should be created for a given cluster
should_create_secrets() {
    local cluster_name=$1
    if [[ -z "$CLUSTER_FILTER" ]]; then
        return 0
    fi
    [[ ",$CLUSTER_FILTER," == *",$cluster_name,"* ]]
}

# Function to create or get secret
create_or_get_secret() {
    local secret_name=$1
    local username=$2
    local password_var_name=$3

    if kubectl get secret "$secret_name" -n "$CAMUNDA_NAMESPACE" >/dev/null 2>&1; then
        echo "Secret $secret_name already exists - retrieving password"
        local existing_password
        existing_password=$(kubectl get secret "$secret_name" -n "$CAMUNDA_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
        printf -v "$password_var_name" '%s' "$existing_password"
    else
        echo "Creating new secret $secret_name"
        local new_password
        new_password=$(openssl rand -base64 18)
        kubectl create secret generic "$secret_name" -n "$CAMUNDA_NAMESPACE" \
          --from-literal=username="$username" \
          --from-literal=password="$new_password" \
          --dry-run=client -o yaml | kubectl apply -f -
        printf -v "$password_var_name" '%s' "$new_password"
    fi
}

echo "Creating PostgreSQL secrets in namespace: $CAMUNDA_NAMESPACE"

# Identity superuser (username=root) and bootstrap (username=identity)
if should_create_secrets "pg-identity"; then
    create_or_get_secret "pg-identity-superuser-secret" "root" "IDENTITY_SUPER_PASS"
    create_or_get_secret "pg-identity-secret" "identity" "IDENTITY_BOOT_PASS"
fi

# Keycloak superuser (username=root) and bootstrap (username=keycloak)
if should_create_secrets "pg-keycloak"; then
    create_or_get_secret "pg-keycloak-superuser-secret" "root" "KEYCLOAK_SUPER_PASS"
    create_or_get_secret "pg-keycloak-secret" "keycloak" "KEYCLOAK_BOOT_PASS"
fi

# Webmodeler superuser (username=root) and bootstrap (username=webmodeler)
if should_create_secrets "pg-webmodeler"; then
    create_or_get_secret "pg-webmodeler-superuser-secret" "root" "WEBM_SUPER_PASS"
    create_or_get_secret "pg-webmodeler-secret" "webmodeler" "WEBM_BOOT_PASS"
fi

# Camunda orchestration superuser (username=root) and bootstrap (username=camunda)
if should_create_secrets "pg-camunda"; then
    create_or_get_secret "pg-camunda-superuser-secret" "root" "CAMUNDA_SUPER_PASS"
    create_or_get_secret "pg-camunda-secret" "camunda" "CAMUNDA_BOOT_PASS"
fi

echo "PostgreSQL secrets created successfully!"
