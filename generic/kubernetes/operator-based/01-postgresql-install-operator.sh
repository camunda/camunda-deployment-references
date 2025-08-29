#!/bin/bash
set -euo pipefail

# Script to install CloudNativePG operator for PostgreSQL
# Creates namespace and installs the operator in cnpg-system namespace

echo "Installing CloudNativePG operator..."

# Create namespace for the operator
kubectl create namespace cnpg-system --dry-run=client -o yaml | kubectl apply -f -

# Install the operator
# TODO(renovate): manage CNPG manifest version via Renovate (auto-bump)
kubectl apply -n cnpg-system --server-side -f \
  "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml"

echo "Waiting for operator to be ready..."
kubectl rollout status deployment \
  -n cnpg-system cnpg-controller-manager

echo "CloudNativePG operator installed successfully!"
