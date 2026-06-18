#!/bin/bash
set -euo pipefail

helm upgrade --install \
  contour contour \
  --repo https://projectcontour.github.io/helm-charts/ \
  --version "$CONTOUR_HELM_CHART_VERSION" \
  --set contour.ingressClass.default=false \
  --set-string 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-backend-protocol=tcp' \
  --set-string 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-cross-zone-load-balancing-enabled=true' \
  --set-string 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-type=nlb' \
  --namespace projectcontour \
  --create-namespace
