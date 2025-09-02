#!/bin/bash
set -euo pipefail

# Script to wait for Elasticsearch cluster to become ready
# Usage: ./02-elasticsearch-wait-ready.sh [namespace] [cluster-name]

NAMESPACE=${1:-camunda}
CLUSTER_NAME=${2:-elasticsearch}

echo "Waiting for Elasticsearch cluster '$CLUSTER_NAME' in namespace: $NAMESPACE"

# Wait up to 10 minutes for health=green and phase=Ready
echo "Waiting for Elasticsearch cluster (max 10m) to reach health=green..."
timeout=600
interval=10
end=$((SECONDS+timeout))

while [ $SECONDS -lt $end ]; do
  health=$(kubectl get elasticsearch "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.health}' 2>/dev/null || true)
  phase=$(kubectl get elasticsearch "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)

  if [ "$health" = "green" ] && [ "$phase" = "Ready" ]; then
    echo "Elasticsearch cluster is ready (health=$health, phase=$phase)."
    break
  fi

  printf "health=%s phase=%s ...\n" "${health:-unknown}" "${phase:-unknown}"
  sleep $interval
done

if [ $SECONDS -ge $end ]; then
  echo "Timeout reached. Current cluster state:"
fi

kubectl get elasticsearch "$CLUSTER_NAME" -n "$NAMESPACE" -o wide || true
kubectl get pods -n "$NAMESPACE" -l elasticsearch.k8s.elastic.co/cluster-name="$CLUSTER_NAME" || true
