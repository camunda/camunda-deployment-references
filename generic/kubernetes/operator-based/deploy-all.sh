#!/bin/bash
set -euo pipefail

# Main deployment script for Camunda infrastructure with operators
# This script orchestrates the installation of all infrastructure components
# Usage: ./deploy-all.sh [namespace] [options]
# Options:
#   --skip-postgresql              Skip PostgreSQL deployment
#   --skip-elasticsearch           Skip Elasticsearch deployment
#   --skip-keycloak               Skip Keycloak deployment
#   --skip-crds                   Skip CRD installation (use existing CRDs)
#   --postgresql-operator-ns NS   Namespace for PostgreSQL operator (default: cnpg-system)
#   --elasticsearch-operator-ns NS Namespace for Elasticsearch operator (default: elastic-system)
#   --keycloak-operator-ns NS     Namespace for Keycloak operator (default: same as app namespace)
#   --help                        Show this help message

# Parse arguments
NAMESPACE="camunda"
POSTGRESQL_OPERATOR_NS="cnpg-system"
ELASTICSEARCH_OPERATOR_NS="elastic-system"
KEYCLOAK_OPERATOR_NS=""  # Will default to same as NAMESPACE
SKIP_POSTGRESQL=false
SKIP_ELASTICSEARCH=false
SKIP_KEYCLOAK=false
SKIP_CRDS=false

show_help() {
    echo "Usage: $0 [namespace] [options]"
    echo ""
    echo "Arguments:"
    echo "  namespace            Kubernetes namespace for applications (default: camunda)"
    echo ""
    echo "Options:"
    echo "  --skip-postgresql              Skip PostgreSQL deployment"
    echo "  --skip-elasticsearch           Skip Elasticsearch deployment"
    echo "  --skip-keycloak               Skip Keycloak deployment"
    echo "  --skip-crds                   Skip CRD installation (use existing CRDs)"
    echo "  --postgresql-operator-ns NS   Namespace for PostgreSQL operator (default: cnpg-system)"
    echo "  --elasticsearch-operator-ns NS Namespace for Elasticsearch operator (default: elastic-system)"
    echo "  --keycloak-operator-ns NS     Namespace for Keycloak operator (default: same as app namespace)"
    echo "  --help                        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                        # Deploy all infrastructure to 'camunda' with default operator namespaces"
    echo "  $0 my-namespace                          # Deploy all infrastructure to 'my-namespace'"
    echo "  $0 --skip-keycloak                       # Deploy only PostgreSQL and Elasticsearch"
    echo "  $0 --skip-crds                           # Deploy without installing CRDs"
    echo "  $0 --postgresql-operator-ns my-pg-ops    # Use custom namespace for PostgreSQL operator"
    echo "  $0 --keycloak-operator-ns keycloak-ops   # Use custom namespace for Keycloak operator"
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
        --skip-crds)
            SKIP_CRDS=true
            shift
            ;;
        --postgresql-operator-ns)
            POSTGRESQL_OPERATOR_NS="$2"
            shift 2
            ;;
        --elasticsearch-operator-ns)
            ELASTICSEARCH_OPERATOR_NS="$2"
            shift 2
            ;;
        --keycloak-operator-ns)
            KEYCLOAK_OPERATOR_NS="$2"
            shift 2
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

# Set default for Keycloak operator namespace if not specified
if [ -z "$KEYCLOAK_OPERATOR_NS" ]; then
    KEYCLOAK_OPERATOR_NS="$NAMESPACE"
fi

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
echo "Application namespace: $NAMESPACE"
echo "PostgreSQL operator: $POSTGRESQL_OPERATOR_NS"
echo "Elasticsearch operator: $ELASTICSEARCH_OPERATOR_NS"
echo "Keycloak operator: $KEYCLOAK_OPERATOR_NS"
echo "PostgreSQL: $([ "$SKIP_POSTGRESQL" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "Elasticsearch: $([ "$SKIP_ELASTICSEARCH" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "Keycloak: $([ "$SKIP_KEYCLOAK" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "CRD Installation: $([ "$SKIP_CRDS" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "========================"

# Create namespaces
echo "Creating application namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl config set-context --current --namespace="$NAMESPACE"

# Step 1: PostgreSQL
if [ "$SKIP_POSTGRESQL" = false ]; then
    echo "=== Installing PostgreSQL Operator ==="
    if [ "$SKIP_CRDS" = false ]; then
        ./01-postgresql-install-operator.sh "$POSTGRESQL_OPERATOR_NS"
    else
        echo "Skipping PostgreSQL CRD installation (--skip-crds specified)"
    fi

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
    if [ "$SKIP_CRDS" = false ]; then
        ./02-elasticsearch-install-operator.sh "$ELASTICSEARCH_OPERATOR_NS"
    else
        echo "Skipping Elasticsearch CRD installation (--skip-crds specified)"
    fi

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
    if [ "$SKIP_CRDS" = false ]; then
        ./03-keycloak-install-operator.sh "$KEYCLOAK_OPERATOR_NS"
    else
        echo "Skipping Keycloak CRD installation (--skip-crds specified)"
    fi

    echo "=== Deploying Keycloak Instance ==="
    envsubst < 03-keycloak-instance.yml | kubectl apply -n "$NAMESPACE" -f -

    echo "=== Waiting for Keycloak Instance ==="
    ./03-keycloak-wait-ready.sh "$NAMESPACE"

    echo "=== Getting Keycloak Admin Credentials ==="
    ./03-keycloak-get-admin-credentials.sh "$NAMESPACE"
else
    echo "=== Skipping Keycloak deployment ==="
fi

echo "=== Running Infrastructure Verification ==="
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
echo "Deployed components in application namespace: $NAMESPACE"
echo "PostgreSQL operator: $POSTGRESQL_OPERATOR_NS"
echo "Elasticsearch operator: $ELASTICSEARCH_OPERATOR_NS"
echo "Keycloak operator: $KEYCLOAK_OPERATOR_NS"
echo ""
echo "Component Status:"
echo "PostgreSQL: $([ "$SKIP_POSTGRESQL" = true ] && echo "SKIPPED" || echo "DEPLOYED")"
echo "Elasticsearch: $([ "$SKIP_ELASTICSEARCH" = true ] && echo "SKIPPED" || echo "DEPLOYED")"
echo "Keycloak: $([ "$SKIP_KEYCLOAK" = true ] && echo "SKIPPED" || echo "DEPLOYED")"
echo "CRDs: $([ "$SKIP_CRDS" = true ] && echo "SKIPPED" || echo "INSTALLED")"

echo ""
echo "🚀 Next Steps:"
echo "1. Deploy Camunda Platform:"
echo "   ./04-camunda-deploy.sh $NAMESPACE"
echo "2. Wait for Camunda to be ready:"
echo "   ./04-camunda-wait-ready.sh $NAMESPACE"
echo "3. Verify Camunda deployment:"
echo "   ./04-camunda-verify.sh $NAMESPACE"

if [ "$SKIP_KEYCLOAK" = false ]; then
    echo ""
    echo "📋 Keycloak Admin Credentials:"
    echo "   ./03-keycloak-get-admin-credentials.sh $NAMESPACE"
    CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
    CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}
    echo "   Access: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/ (via port-forward)"
fi
