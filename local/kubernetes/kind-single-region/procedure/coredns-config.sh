#!/bin/bash
set -euo pipefail

# Configure CoreDNS to resolve camunda.example.com inside pods
# Usage: ./procedure/coredns-config.sh
# Run from: local/kubernetes/kind-single-region/

echo "Applying CoreDNS configuration for Contour..."

kubectl apply -f configs/coredns-configmap-contour.yaml

echo "Restarting CoreDNS..."
kubectl delete pod -n kube-system -l k8s-app=kube-dns

echo "CoreDNS configured for camunda.example.com (ingress: Contour)"
