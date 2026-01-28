#!/bin/bash
# Deploy Elasticsearch via ECK operator for AKS

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
OPERATOR_NAMESPACE=${1:-elastic-system}

# renovate: datasource=github-releases depName=elastic/cloud-on-k8s
ECK_VERSION="3.2.0"

echo "Installing ECK operator CRDs..."
kubectl apply --server-side -f \
  "https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml"

# Create operator namespace if needed
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install ECK operator
echo "Installing ECK operator in namespace: $OPERATOR_NAMESPACE"
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f \
  "https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml"

# Wait for operator to be ready
echo "Waiting for ECK operator to be ready..."
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 --timeout=300s statefulset/elastic-operator -n "$OPERATOR_NAMESPACE"

# Deploy Elasticsearch cluster
echo "Deploying Elasticsearch cluster in namespace: $CAMUNDA_NAMESPACE"
kubectl apply -f "../manifests/elasticsearch-cluster.yml" -n "$CAMUNDA_NAMESPACE"

# Wait for Elasticsearch cluster to be ready
echo "Waiting for Elasticsearch cluster to be ready..."
kubectl wait --for=jsonpath='{.status.phase}'=Ready --timeout=600s elasticsearch --all -n "$CAMUNDA_NAMESPACE"

echo "Elasticsearch deployment completed successfully!"
