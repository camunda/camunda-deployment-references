#!/bin/bash
set -euo pipefail

# Script to update Keycloak realm configuration
# Usage: ./03-keycloak-update-realm.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Updating Keycloak realm configuration in namespace: $NAMESPACE"

# Check if ConfigMap exists
if ! kubectl get configmap keycloak-realm-config -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Error: ConfigMap 'keycloak-realm-config' not found in namespace $NAMESPACE"
    echo "Please run: ./03-keycloak-create-realm-configmap.sh $NAMESPACE"
    exit 1
fi

# Recreate the ConfigMap with updated realm configuration
echo "=== Updating Keycloak Realm ConfigMap ==="
./03-keycloak-create-realm-configmap.sh "$NAMESPACE"

# Restart Keycloak pods to pick up the new configuration
echo "=== Restarting Keycloak Pods ==="
kubectl rollout restart statefulset/keycloak -n "$NAMESPACE"

echo "=== Waiting for Keycloak Rollout ==="
kubectl rollout status statefulset/keycloak -n "$NAMESPACE" --timeout=300s

echo "Keycloak realm configuration updated successfully!"
echo "The realm will be reimported on next startup."
echo
echo "Note: For updates to existing realms, you may need to:"
echo "1. Delete the existing realm in Keycloak admin console"
echo "2. Or manually apply changes through the admin console"
echo "3. Or use Keycloak Admin REST API for programmatic updates"
