#!/bin/bash
set -euo pipefail

# Script to verify Camunda Platform deployment with operator-based infrastructure
# Usage: ./04-camunda-verify.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Verifying Camunda Platform deployment in namespace: $NAMESPACE"

echo "=== Checking Helm Release ==="
helm list -n "$NAMESPACE" | grep camunda || echo "No Camunda release found"
echo

echo "=== Checking Camunda Platform Pods ==="
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/part-of=camunda-platform
echo

echo "=== Checking Camunda Platform Services ==="
kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/part-of=camunda-platform
echo

echo "=== Checking Pod Status by Component ==="
components=("identity" "operate" "optimize" "tasklist" "zeebe" "zeebe-gateway" "connectors" "webModeler" "console")

for component in "${components[@]}"; do
    echo "--- $component ---"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component="$component" --no-headers | awk '{print $1 ": " $3}' || echo "Component $component not found"
done
echo

echo "=== Checking External Dependencies ==="
echo "PostgreSQL clusters:"
kubectl get clusters.postgresql.cnpg.io -n "$NAMESPACE" || echo "No PostgreSQL clusters found"
echo

echo "Elasticsearch cluster:"
kubectl get elasticsearch -n "$NAMESPACE" || echo "No Elasticsearch cluster found"
echo

echo "Keycloak instance:"
kubectl get keycloak -n "$NAMESPACE" || echo "No Keycloak instance found"
echo

echo "=== Checking ConfigMaps and Secrets ==="
echo "PostgreSQL secrets:"
kubectl get secrets -n "$NAMESPACE" | grep "^pg-" || echo "No PostgreSQL secrets found"
echo

echo "Identity secrets:"
kubectl get secrets -n "$NAMESPACE" | grep identity || echo "No Identity secrets found"
echo

echo "=== Access Information ==="
CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}

echo "Camunda Platform Access URLs:"
echo "- Identity: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/identity"
echo "- Operate: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/operate"
echo "- Optimize: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/optimize"
echo "- Tasklist: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/tasklist"
echo "- WebModeler: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/modeler"
echo "- Console: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/console"
echo "- Keycloak Admin: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/"
echo

echo "=== Quick Health Check ==="
failed_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -v "Running\|Completed" | grep -c "." || echo "0")
if [ "$failed_pods" -eq 0 ]; then
    echo "✓ All pods are running or completed"
else
    echo "⚠️  $failed_pods pod(s) are not in Running/Completed state"
    kubectl get pods -n "$NAMESPACE" | grep -v "Running\|Completed" | grep -v "NAME" || true
fi

echo ""
echo "Camunda Platform verification completed."
