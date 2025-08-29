#!/bin/bash
set -euo pipefail

# Script to install Elastic Cloud on Kubernetes (ECK) operator
# Creates namespace and installs the operator in elastic-system namespace

echo "Installing ECK (Elastic Cloud on Kubernetes) operator..."

# Install CRDs first
kubectl apply --server-side -f \
  https://download.elastic.co/downloads/eck/3.1.0/crds.yaml

echo "Waiting for CRDs to be established..."
sleep 10

# Create namespace for the operator
kubectl create namespace elastic-system --dry-run=client -o yaml | kubectl apply -f -

# Install the operator
kubectl apply -n elastic-system --server-side -f \
  https://download.elastic.co/downloads/eck/3.1.0/operator.yaml

echo "Waiting for operator to be ready..."
kubectl wait --for=condition=ready pod -l name=elastic-operator -n elastic-system --timeout=300s

echo "ECK operator installed successfully!"
