#!/bin/bash
set -euo pipefail

# Script to get Elasticsearch admin credentials from ECK-generated secret
# Usage: ./02-elasticsearch-get-admin-credentials.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Retrieving Elasticsearch admin credentials from namespace: $NAMESPACE"

# Check if the ECK-generated secret exists
if ! kubectl get secret elasticsearch-es-elastic-user -n "$NAMESPACE" &>/dev/null; then
    echo "Error: ECK-generated secret 'elasticsearch-es-elastic-user' not found in namespace '$NAMESPACE'"
    echo "Make sure Elasticsearch cluster is deployed and ready first."
    exit 1
fi

echo
echo "Elasticsearch connection details:"
echo "URL: https://elasticsearch-es-http.$NAMESPACE.svc.cluster.local:9200"
echo "Admin Username: elastic"
echo "Admin Password:"
kubectl -n "$NAMESPACE" get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode
echo
echo "To access Elasticsearch:"
echo "1. Port-forward: kubectl -n $NAMESPACE port-forward svc/elasticsearch-es-http 9200:9200"
echo "2. Test connection: curl -u elastic:<password> https://localhost:9200"
