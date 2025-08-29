#!/bin/bash
set -euo pipefail

# Script to verify Elasticsearch installation and cluster
# Usage: ./02-elasticsearch-verify.sh [namespace] [cluster-name]

NAMESPACE=${1:-camunda}
CLUSTER_NAME=${2:-elasticsearch}

echo "Verifying Elasticsearch installation in namespace: $NAMESPACE"

echo "=== Checking ECK Operator ==="
kubectl get pods -n elastic-system -l name=elastic-operator
echo

echo "=== Checking Elasticsearch Cluster Status ==="
kubectl get elasticsearch "$CLUSTER_NAME" -n "$NAMESPACE" -o wide
echo

echo "=== Checking Elasticsearch Services ==="
kubectl -n "$NAMESPACE" get svc | grep "elasticsearch" || true
echo

echo "=== Checking Elasticsearch Pods ==="
kubectl get pods -n "$NAMESPACE" -l elasticsearch.k8s.elastic.co/cluster-name="$CLUSTER_NAME" || true
echo

echo "=== Checking Elasticsearch Secret ==="
if kubectl get secret elasticsearch-es-elastic-user -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Elasticsearch secret exists"
    echo "Username: elastic"
    echo "Password length: $(kubectl get secret elasticsearch-es-elastic-user -n "$NAMESPACE" -o jsonpath='{.data.elastic}' | base64 --decode | wc -c) characters"
else
    echo "Elasticsearch secret not found!"
fi
echo

echo "=== Elasticsearch Health Check ==="
# Try to check cluster health via port-forward (optional)
echo "To manually check cluster health, run:"
echo "kubectl port-forward -n $NAMESPACE svc/elasticsearch-es-http 9200:9200"
echo "curl -u elastic:\$(kubectl get secret elasticsearch-es-elastic-user -n $NAMESPACE -o jsonpath='{.data.elastic}' | base64 --decode) http://localhost:9200/_cluster/health"
echo

echo "Elasticsearch verification completed."
