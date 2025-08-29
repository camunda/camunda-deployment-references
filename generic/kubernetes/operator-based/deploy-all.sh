#!/bin/bash
set -euo pipefail

# Main deployment script for Camunda infrastructure with operators
# This script orchestrates the installation of all components
# Usage: ./deploy-all.sh [namespace] [options]
# Options:
#   --skip-postgresql    Skip PostgreSQL deployment
#   --skip-elasticsearch Skip Elasticsearch deployment
#   --skip-keycloak      Skip Keycloak deployment
#   --help               Show this help message

# Parse arguments
NAMESPACE="camunda"
SKIP_POSTGRESQL=false
SKIP_ELASTICSEARCH=false
SKIP_KEYCLOAK=false

show_help() {
    echo "Usage: $0 [namespace] [options]"
    echo ""
    echo "Arguments:"
    echo "  namespace            Kubernetes namespace (default: camunda)"
    echo ""
    echo "Options:"
    echo "  --skip-postgresql    Skip PostgreSQL deployment"
    echo "  --skip-elasticsearch Skip Elasticsearch deployment"
    echo "  --skip-keycloak      Skip Keycloak deployment"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Deploy all components to 'camunda' namespace"
    echo "  $0 my-namespace             # Deploy all components to 'my-namespace'"
    echo "  $0 --skip-keycloak          # Deploy only PostgreSQL and Elasticsearch"
    echo "  $0 my-ns --skip-postgresql  # Deploy only Elasticsearch and Keycloak to 'my-ns'"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-postgresql)
            SKIP_POSTGRESQL=true
            shift
            ;;
        --skip-elasticsearch)
            SKIP_ELASTICSEARCH=true
            shift
            ;;
        --skip-keycloak)
            SKIP_KEYCLOAK=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option $1"
            show_help
            exit 1
            ;;
        *)
            NAMESPACE="$1"
            shift
            ;;
    esac
done

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

# Show deployment plan
echo "=== Deployment Plan ==="
echo "Namespace: $NAMESPACE"
echo "PostgreSQL: $([ "$SKIP_POSTGRESQL" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "Elasticsearch: $([ "$SKIP_ELASTICSEARCH" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "Keycloak: $([ "$SKIP_KEYCLOAK" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "========================"

# Create namespace
echo "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace="$NAMESPACE"

# Step 1: PostgreSQL
if [ "$SKIP_POSTGRESQL" = false ]; then
    echo "=== Installing PostgreSQL Operator ==="
    ./01-postgresql-install-operator.sh

    echo "=== Creating PostgreSQL Secrets ==="
    ./01-postgresql-create-secrets.sh "$NAMESPACE"

    echo "=== Deploying PostgreSQL Clusters ==="
    kubectl apply -n "$NAMESPACE" -f 01-postgresql-clusters.yml

    echo "=== Waiting for PostgreSQL Clusters ==="
    ./01-postgresql-wait-ready.sh "$NAMESPACE"
else
    echo "=== Skipping PostgreSQL deployment ==="
fi

# Step 2: Elasticsearch
if [ "$SKIP_ELASTICSEARCH" = false ]; then
    echo "=== Installing Elasticsearch Operator ==="
    ./02-elasticsearch-install-operator.sh

    echo "=== Deploying Elasticsearch Cluster ==="
    kubectl apply -n "$NAMESPACE" -f 02-elasticsearch-cluster.yml

    echo "=== Waiting for Elasticsearch Cluster ==="
    ./02-elasticsearch-wait-ready.sh "$NAMESPACE"
else
    echo "=== Skipping Elasticsearch deployment ==="
fi

# Step 3: Keycloak
if [ "$SKIP_KEYCLOAK" = false ]; then
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
else
    echo "=== Skipping Keycloak deployment ==="
fi

echo "=== Running Component Verification ==="
# Only verify deployed components - pass the same skip flags
if [ "$SKIP_POSTGRESQL" = false ] || [ "$SKIP_ELASTICSEARCH" = false ] || [ "$SKIP_KEYCLOAK" = false ]; then
    VERIFY_ARGS="$NAMESPACE"
    [ "$SKIP_POSTGRESQL" = true ] && VERIFY_ARGS="$VERIFY_ARGS --skip-postgresql"
    [ "$SKIP_ELASTICSEARCH" = true ] && VERIFY_ARGS="$VERIFY_ARGS --skip-elasticsearch"
    [ "$SKIP_KEYCLOAK" = true ] && VERIFY_ARGS="$VERIFY_ARGS --skip-keycloak"

    ./verify-all.sh "$VERIFY_ARGS"
else
    echo "No components deployed - skipping verification"
fi

echo "Infrastructure deployment completed successfully!"
echo "Deployed components in namespace: $NAMESPACE"
echo "PostgreSQL: $([ "$SKIP_POSTGRESQL" = true ] && echo "SKIPPED" || echo "DEPLOYED")"
echo "Elasticsearch: $([ "$SKIP_ELASTICSEARCH" = true ] && echo "SKIPPED" || echo "DEPLOYED")"
echo "Keycloak: $([ "$SKIP_KEYCLOAK" = true ] && echo "SKIPPED" || echo "DEPLOYED")"
