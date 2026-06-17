#!/bin/bash
set -euo pipefail

helm upgrade --install \
  contour contour \
  --repo https://projectcontour.github.io/helm-charts/ \
  --version "$CONTOUR_HELM_CHART_VERSION" \
  --set 'contour.replicaCount=2' \
  --set 'envoy.service.externalTrafficPolicy=Local' \
  --set-string 'envoy.service.annotations.service\.beta\.kubernetes\.io\/azure-load-balancer-health-probe-request-path=/healthz' \
  --namespace projectcontour \
  --create-namespace
