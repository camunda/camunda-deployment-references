#!/bin/bash
set -euo pipefail

# Script to get Keycloak admin credentials
# Usage: ./03-keycloak-get-admin-credentials.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Retrieving Keycloak admin credentials from namespace: $NAMESPACE"

echo "Admin Username:"
kubectl -n "$NAMESPACE" get secret keycloak-initial-admin -o jsonpath='{.data.username}' | base64 --decode
echo

echo "Admin Password:"
kubectl -n "$NAMESPACE" get secret keycloak-initial-admin -o jsonpath='{.data.password}' | base64 --decode
echo

echo
echo "To access Keycloak admin console:"
echo "1. Port-forward: kubectl -n $NAMESPACE port-forward svc/keycloak 8080:8080"
echo "2. Open: http://localhost:8080/admin/"
