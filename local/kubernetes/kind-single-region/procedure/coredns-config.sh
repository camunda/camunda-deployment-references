#!/bin/bash
set -euo pipefail

# Configure CoreDNS to resolve camunda.example.com inside pods
# Usage: ./procedure/coredns-config.sh [nginx|contour]
# Run from: local/kubernetes/kind-single-region/

INGRESS="${1:-contour}"

case "$INGRESS" in
  nginx)
    CONFIGMAP="configs/coredns-configmap.yaml"
    ;;
  contour)
    CONFIGMAP="configs/coredns-configmap-contour.yaml"
    ;;
  *)
    echo "Error: unknown ingress controller '$INGRESS'. Use 'nginx' or 'contour'."
    exit 1
    ;;
esac

echo "Applying CoreDNS configuration for $INGRESS ingress controller..."

kubectl apply -f "$CONFIGMAP"

echo "Restarting CoreDNS..."
kubectl delete pod -n kube-system -l k8s-app=kube-dns

echo "CoreDNS configured for camunda.example.com (ingress: $INGRESS)"
