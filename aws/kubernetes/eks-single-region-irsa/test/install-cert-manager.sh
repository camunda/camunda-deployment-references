#!/bin/bash

# Install cert-manager with wildcard cluster issuer as default
# This is an alternative to the standard procedure that uses ACME/Let's Encrypt

set -euo pipefail

helm upgrade --install \
  cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --version "$CERT_MANAGER_HELM_CHART_VERSION" \
  --namespace cert-manager \
  --create-namespace \
  --set "serviceAccount.annotations.eks\.amazonaws\.com\/role-arn=$CERT_MANAGER_IRSA_ARN" \
  --set securityContext.fsGroup=1001 \
  --set ingressShim.defaultIssuerName=wildcard-cluster-issuer \
  --set ingressShim.defaultIssuerKind=ClusterIssuer \
  --set ingressShim.defaultIssuerGroup=cert-manager.ioc
