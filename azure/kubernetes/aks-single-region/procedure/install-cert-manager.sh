#!/bin/bash

helm upgrade --install \
  cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --version "$CERT_MANAGER_HELM_CHART_VERSION" \
  --namespace cert-manager \
  --create-namespace \
  --set securityContext.fsGroup=1001 \
  --set ingressShim.defaultIssuerName=letsencrypt \
  --set ingressShim.defaultIssuerKind=ClusterIssuer \
  --set ingressShim.defaultIssuerGroup=cert-manager.io
