#!/bin/bash
set -euo pipefail

# Main deployment script for Camunda infrastructure with operators
# This script orchestrates the installation of all components

NAMESPACE=${1:-camunda}

echo "Starting Camunda infrastructure deployment in namespace: $NAMESPACE"

# Check required environment variables
echo "=== Checking Environment Variables ==="
export CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
export CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}

echo "Using CAMUNDA_DOMAIN: $CAMUNDA_DOMAIN"
echo "Using CAMUNDA_PROTOCOL: $CAMUNDA_PROTOCOL"

# Verify envsubst is available
if ! command -v envsubst &> /dev/null; then
    echo "Error: envsubst is required but not installed"
    echo "On macOS: brew install gettext"
    echo "On Ubuntu/Debian: apt-get install gettext-base"
    exit 1
fi

echo "Starting Camunda infrastructure deployment in namespace: $NAMESPACE"

# Create namespace
echo "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace="$NAMESPACE"

# Step 1: PostgreSQL
echo "=== Installing PostgreSQL Operator ==="
./01-postgresql-install-operator.sh

echo "=== Creating PostgreSQL Secrets ==="
./01-postgresql-create-secrets.sh "$NAMESPACE"

echo "=== Deploying PostgreSQL Clusters ==="
kubectl apply -n "$NAMESPACE" -f 01-postgresql-clusters.yml

echo "=== Waiting for PostgreSQL Clusters ==="
./01-postgresql-wait-ready.sh "$NAMESPACE"

# Step 2: Elasticsearch
echo "=== Installing Elasticsearch Operator ==="
./02-elasticsearch-install-operator.sh

echo "=== Deploying Elasticsearch Cluster ==="
kubectl apply -n "$NAMESPACE" -f 02-elasticsearch-cluster.yml

echo "=== Waiting for Elasticsearch Cluster ==="
./02-elasticsearch-wait-ready.sh "$NAMESPACE"

# Step 3: Keycloak
echo "=== Installing Keycloak Operator ==="
./03-keycloak-install-operator.sh "$NAMESPACE"

echo "=== Creating Keycloak Realm Secrets ==="
./03-keycloak-create-realm-secrets.sh "$NAMESPACE"

echo "=== Deploying Keycloak Instance with Realm Auto-Import ==="
./03-keycloak-deploy-with-realm.sh "$NAMESPACE"

echo "=== Waiting for Keycloak Instance ==="
./03-keycloak-wait-ready.sh "$NAMESPACE"

echo "=== Deploying Keycloak Ingress ==="
envsubst < 03-keycloak-ingress.yml | kubectl apply -n "$NAMESPACE" -f -

echo "=== Getting Keycloak Admin Credentials ==="
./03-keycloak-get-admin-credentials.sh "$NAMESPACE"

echo "=== Running Complete Verification ==="
./verify-all.sh "$NAMESPACE"

echo "Infrastructure deployment completed successfully!"
echo "All components are ready in namespace: $NAMESPACE"
