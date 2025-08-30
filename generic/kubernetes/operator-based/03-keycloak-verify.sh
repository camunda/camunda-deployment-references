#!/bin/bash
set -euo pipefail

# Script to verify Keycloak installation and instance
# Usage: ./03-keycloak-verify.sh [namespace] [instance-name]

NAMESPACE=${1:-camunda}
INSTANCE_NAME=${2:-keycloak}

echo "Verifying Keycloak installation in namespace: $NAMESPACE"

echo "=== Checking Keycloak Operator ==="
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak-operator
echo

echo "=== Checking Keycloak Instance Status ==="
kubectl get keycloak "$INSTANCE_NAME" -n "$NAMESPACE" -o wide
echo

echo "=== Checking Keycloak Services ==="
kubectl get svc -n "$NAMESPACE" | grep keycloak || true
echo

echo "=== Checking Keycloak Ingress ==="
kubectl get ingress -n "$NAMESPACE" | grep keycloak || echo "No Keycloak ingress found"
echo

echo "=== Checking Keycloak Pods ==="
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak,app.kubernetes.io/instance="$INSTANCE_NAME" || true
echo

echo "=== Checking Keycloak Admin Credentials ==="
if kubectl get secret keycloak-initial-admin -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Keycloak admin secret exists"
    echo "Admin Username: $(kubectl get secret keycloak-initial-admin -n "$NAMESPACE" -o jsonpath='{.data.username}' | base64 --decode)"
    echo "Admin Password: $(kubectl get secret keycloak-initial-admin -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 --decode)"
else
    echo "Keycloak admin secret not found!"
fi
echo

echo "=== Keycloak Database Connection ==="
echo "Keycloak is configured to use PostgreSQL cluster: pg-keycloak-rw"
kubectl get svc pg-keycloak-rw -n "$NAMESPACE" >/dev/null 2>&1 && echo "PostgreSQL service for Keycloak is available" || echo "PostgreSQL service for Keycloak not found!"
echo

echo "=== Access Instructions ==="
CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}

echo "To access Keycloak admin console:"
if kubectl get ingress keycloak -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "1. Via Ingress: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/"
    echo "2. Alternative port-forward: kubectl -n $NAMESPACE port-forward svc/keycloak 8080:8080"
    echo "   Then open: http://localhost:8080/auth/admin/"
else
    echo "1. Port-forward: kubectl -n $NAMESPACE port-forward svc/keycloak 8080:8080"
    echo "2. Open: http://localhost:8080/auth/admin/"
fi
echo "3. Login with the credentials shown above"
echo

echo "Keycloak verification completed."
