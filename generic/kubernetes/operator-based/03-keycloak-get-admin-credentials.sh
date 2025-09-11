#!/bin/bash
set -euo pipefail

# Script to get Keycloak admin credentials
# Usage: ./03-keycloak-get-admin-credentials.sh [namespace]

NAMESPACE=${1:-$CAMUNDA_NAMESPACE}

echo "Retrieving Keycloak admin credentials from namespace: $NAMESPACE"

echo "Admin Username:"
kubectl -n "$NAMESPACE" get secret keycloak-initial-admin -o jsonpath='{.data.username}' | base64 --decode
echo

echo "Admin Password:"
kubectl -n "$NAMESPACE" get secret keycloak-initial-admin -o jsonpath='{.data.password}' | base64 --decode
echo
