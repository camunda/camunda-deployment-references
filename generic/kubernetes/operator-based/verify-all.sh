#!/bin/bash
set -euo pipefail

# Complete verification script for all Camunda infrastructure components
# Usage: ./verify-all.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Starting complete verification of Camunda infrastructure in namespace: $NAMESPACE"
echo "=================================================================="

echo
echo "🔍 STEP 1: Verifying PostgreSQL Components"
echo "-------------------------------------------"
./01-postgresql-verify.sh "$NAMESPACE"

echo
echo "🔍 STEP 2: Verifying Elasticsearch Components"
echo "----------------------------------------------"
./02-elasticsearch-verify.sh "$NAMESPACE"

echo
echo "🔍 STEP 3: Verifying Keycloak Components"
echo "-----------------------------------------"
./03-keycloak-verify.sh "$NAMESPACE"

echo
echo "=================================================================="
echo "✅ Complete infrastructure verification finished!"
echo "All components have been verified in namespace: $NAMESPACE"
echo
echo "Next steps:"
echo "- Configure Keycloak realm for Camunda"
echo "- Install Camunda Helm chart"
echo "=================================================================="
