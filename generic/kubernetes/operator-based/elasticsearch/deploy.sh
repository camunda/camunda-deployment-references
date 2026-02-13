#!/bin/bash
# elasticsearch/deploy.sh - Deploy Elasticsearch via ECK operator

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
OPERATOR_NAMESPACE=${1:-elastic-system}
ELASTICSEARCH_CLUSTER_FILE=${ELASTICSEARCH_CLUSTER_FILE:-elasticsearch-cluster.yml}

# renovate: datasource=github-releases depName=elastic/cloud-on-k8s
ECK_VERSION="3.3.0"

# Install ECK operator CRDs
kubectl apply --server-side -f \
  "https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml"

# Create operator namespace if needed
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install ECK operator
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side  -f \
  "https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml"
echo "ECK operator deployed in namespace: $OPERATOR_NAMESPACE"

# Wait for operator to be ready
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 --timeout=300s statefulset/elastic-operator -n "$OPERATOR_NAMESPACE"

# Deploy Elasticsearch cluster
kubectl apply -f "$ELASTICSEARCH_CLUSTER_FILE" -n "$CAMUNDA_NAMESPACE"

# Wait for Elasticsearch cluster to be ready
kubectl wait --for=jsonpath='{.status.phase}'=Ready --timeout=600s elasticsearch --all -n "$CAMUNDA_NAMESPACE"

echo "Elasticsearch deployment completed in namespace: $CAMUNDA_NAMESPACE"
