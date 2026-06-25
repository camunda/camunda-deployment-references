#!/bin/bash
set -euo pipefail

# Configure CoreDNS to resolve camunda.example.com inside pods
# Run from: local/kubernetes/kind-single-region/

CONFIGMAP="configs/coredns-configmap-contour.yaml"

echo "Applying CoreDNS configuration for the Contour ingress controller..."

kubectl apply -f "$CONFIGMAP"

echo "Restarting CoreDNS..."
kubectl delete pod -n kube-system -l k8s-app=kube-dns

echo "CoreDNS configured for camunda.example.com (ingress: contour)"
