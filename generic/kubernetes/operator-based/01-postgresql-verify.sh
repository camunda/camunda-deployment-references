#!/bin/bash
set -euo pipefail

# Script to verify PostgreSQL installation and clusters
# Usage: ./01-postgresql-verify.sh [namespace]

NAMESPACE=${1:-$CAMUNDA_NAMESPACE}

echo "Verifying PostgreSQL installation in namespace: $NAMESPACE"

echo "=== Checking CloudNativePG Operator ==="
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
echo

echo "=== Checking PostgreSQL Clusters Status ==="
kubectl get clusters -n "$NAMESPACE"
echo

echo "=== Checking PostgreSQL Services ==="
kubectl -n "$NAMESPACE" get svc | grep "pg-" || true
echo

echo "=== Checking PostgreSQL Secrets ==="
echo "Secrets for PostgreSQL clusters:"
kubectl get secrets -n "$NAMESPACE" | grep "pg-" || true
echo

echo "=== Testing Secret Access (Identity example) ==="
if kubectl get secret pg-identity-superuser-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Identity superuser secret exists"
    echo "Username: $(kubectl get secret pg-identity-superuser-secret -n "$NAMESPACE" -o jsonpath='{.data.username}' | base64 --decode)"
    echo "Password length: $(kubectl get secret pg-identity-superuser-secret -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 --decode | wc -c) characters"
else
    echo "Identity superuser secret not found!"
fi
echo

echo "=== PostgreSQL Pods Status ==="
kubectl get pods -n "$NAMESPACE" -l cnpg.io/cluster || true
echo

echo "PostgreSQL verification completed."
