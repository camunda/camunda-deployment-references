#!/bin/bash
set -euo pipefail

# Script to create PostgreSQL secrets for CloudNativePG clusters
# Run this in the camunda namespace

NAMESPACE=${1:-camunda}

echo "Creating PostgreSQL secrets in namespace: $NAMESPACE"

# Identity superuser (username=root) and bootstrap (username=identity)
IDENTITY_SUPER_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-identity-superuser-secret -n "$NAMESPACE" \
  --from-literal=username=root \
  --from-literal=password="$IDENTITY_SUPER_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

IDENTITY_BOOT_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-identity-secret -n "$NAMESPACE" \
  --from-literal=username=identity \
  --from-literal=password="$IDENTITY_BOOT_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# Keycloak superuser (username=root) and bootstrap (username=keycloak)
KEYCLOAK_SUPER_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-keycloak-superuser-secret -n "$NAMESPACE" \
  --from-literal=username=root \
  --from-literal=password="$KEYCLOAK_SUPER_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

KEYCLOAK_BOOT_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-keycloak-secret -n "$NAMESPACE" \
  --from-literal=username=keycloak \
  --from-literal=password="$KEYCLOAK_BOOT_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# Webmodeler superuser (username=root) and bootstrap (username=webmodeler)
WEBM_SUPER_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-webmodeler-superuser-secret -n "$NAMESPACE" \
  --from-literal=username=root \
  --from-literal=password="$WEBM_SUPER_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

WEBM_BOOT_PASS=$(openssl rand -base64 18)
kubectl create secret generic pg-webmodeler-secret -n "$NAMESPACE" \
  --from-literal=username=webmodeler \
  --from-literal=password="$WEBM_BOOT_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "PostgreSQL secrets created successfully!"
echo "Identity superuser password: $IDENTITY_SUPER_PASS"
echo "Identity user password: $IDENTITY_BOOT_PASS"
echo "Keycloak superuser password: $KEYCLOAK_SUPER_PASS"
echo "Keycloak user password: $KEYCLOAK_BOOT_PASS"
echo "Webmodeler superuser password: $WEBM_SUPER_PASS"
echo "Webmodeler user password: $WEBM_BOOT_PASS"
