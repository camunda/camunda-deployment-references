#!/bin/bash
set -euo pipefail

# Create Kind cluster for Camunda Platform local development
# Run from: local/kubernetes/kind-single-region/

echo "Creating Kind cluster: camunda-platform-local"

kind create cluster --config configs/kind-cluster-config.yaml

echo "Waiting for cluster nodes to be ready..."
kubectl cluster-info --context kind-camunda-platform-local
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes -o wide

kubectl create namespace camunda --dry-run=client -o yaml | kubectl apply -f -

echo "Kind cluster created successfully"
