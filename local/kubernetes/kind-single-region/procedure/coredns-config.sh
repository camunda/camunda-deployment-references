#!/bin/bash
set -euo pipefail

# Configure CoreDNS to resolve camunda.example.com inside pods
# Run from: local/kubernetes/kind-single-region/

echo "Applying CoreDNS configuration for domain resolution..."

kubectl apply -f configs/coredns-configmap.yaml

echo "Restarting CoreDNS..."
kubectl delete pod -n kube-system -l k8s-app=kube-dns

echo "CoreDNS configured for camunda.example.com"
