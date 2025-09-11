#!/bin/bash
set -euo pipefail

# Script to wait for PostgreSQL clusters to become healthy
# Usage: ./01-postgresql-wait-ready.sh [namespace]

NAMESPACE=${1:-$CAMUNDA_NAMESPACE}

echo "Waiting for PostgreSQL clusters in namespace: $NAMESPACE"

# Wait up to 5 minutes (300s), polling every 5s, then display the final state
echo "Waiting for clusters (max 5m) to become 'healthy'..."
timeout=300
interval=5
end=$((SECONDS+timeout))

while [ $SECONDS -lt $end ]; do
  count=$(kubectl get clusters -n "$NAMESPACE" 2>/dev/null | grep -E '^pg-(identity|keycloak|webmodeler)\b' | grep -c 'Cluster in healthy state' || true)
  if [ "$count" -eq 3 ]; then
    echo "All clusters are in 'healthy' state."
    break
  fi
  echo "Clusters ready: $count/3"
  sleep $interval
done

if [ $SECONDS -ge $end ]; then
  echo "Timeout reached. Current cluster state:"
fi

kubectl get clusters -n "$NAMESPACE"
