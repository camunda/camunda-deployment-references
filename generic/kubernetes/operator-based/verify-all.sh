#!/bin/bash
set -euo pipefail

# Complete verification script for all Camunda infrastructure components
# Usage: ./verify-all.sh [namespace] [options]
# Options:
#   --skip-postgresql    Skip PostgreSQL verification
#   --skip-elasticsearch Skip Elasticsearch verification
#   --skip-keycloak      Skip Keycloak verification
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
    echo "  --skip-postgresql    Skip PostgreSQL verification"
    echo "  --skip-elasticsearch Skip Elasticsearch verification"
    echo "  --skip-keycloak      Skip Keycloak verification"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Verify all components in 'camunda' namespace"
    echo "  $0 my-namespace             # Verify all components in 'my-namespace'"
    echo "  $0 --skip-keycloak          # Verify only PostgreSQL and Elasticsearch"
    echo "  $0 my-ns --skip-postgresql  # Verify only Elasticsearch and Keycloak in 'my-ns'"
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

echo "Starting complete verification of Camunda infrastructure in namespace: $NAMESPACE"

# Show verification plan
echo "=== Verification Plan ==="
echo "Namespace: $NAMESPACE"
echo "PostgreSQL: $([ "$SKIP_POSTGRESQL" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "Elasticsearch: $([ "$SKIP_ELASTICSEARCH" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "Keycloak: $([ "$SKIP_KEYCLOAK" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo "=========================="

echo "=================================================================="

echo

# Step 1: PostgreSQL verification
if [ "$SKIP_POSTGRESQL" = false ]; then
    echo "🔍 STEP 1: Verifying PostgreSQL Components"
    echo "-------------------------------------------"
    ./01-postgresql-verify.sh "$NAMESPACE"
else
    echo "⏭️  STEP 1: Skipping PostgreSQL verification"
fi

echo

# Step 2: Elasticsearch verification
if [ "$SKIP_ELASTICSEARCH" = false ]; then
    echo "🔍 STEP 2: Verifying Elasticsearch Components"
    echo "----------------------------------------------"
    ./02-elasticsearch-verify.sh "$NAMESPACE"
else
    echo "⏭️  STEP 2: Skipping Elasticsearch verification"
fi

echo

# Step 3: Keycloak verification
if [ "$SKIP_KEYCLOAK" = false ]; then
    echo "🔍 STEP 3: Verifying Keycloak Components"
    echo "-----------------------------------------"
    ./03-keycloak-verify.sh "$NAMESPACE"
else
    echo "⏭️  STEP 3: Skipping Keycloak verification"
fi

echo
echo "=================================================================="
echo "✅ Infrastructure verification completed!"
echo "Verification summary for namespace: $NAMESPACE"
echo "PostgreSQL: $([ "$SKIP_POSTGRESQL" = true ] && echo "SKIPPED" || echo "VERIFIED")"
echo "Elasticsearch: $([ "$SKIP_ELASTICSEARCH" = true ] && echo "SKIPPED" || echo "VERIFIED")"
echo "Keycloak: $([ "$SKIP_KEYCLOAK" = true ] && echo "SKIPPED" || echo "VERIFIED")"
echo

# Only show next steps if any components were verified
if [ "$SKIP_POSTGRESQL" = false ] || [ "$SKIP_ELASTICSEARCH" = false ] || [ "$SKIP_KEYCLOAK" = false ]; then
    echo "Next steps:"
    echo "- Install Camunda Helm chart"
else
    echo "No components were verified"
fi
echo "=================================================================="
