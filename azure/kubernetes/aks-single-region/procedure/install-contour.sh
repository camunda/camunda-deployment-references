#!/bin/bash
set -euo pipefail

# envoy.service.externalTrafficPolicy=Local is already the chart default, but we keep
# it explicit because the Azure LB health-probe annotation below relies on it: with
# "Local" the probe targets the Kubernetes healthCheckNodePort instead of a random node.
helm upgrade --install \
  contour contour \
  --repo https://projectcontour.github.io/helm-charts/ \
  --version "$CONTOUR_HELM_CHART_VERSION" \
  --set 'contour.ingressClass.default=false' \
  --set 'contour.replicaCount=2' \
  --set 'envoy.service.externalTrafficPolicy=Local' \
  --set-string 'envoy.service.annotations.service\.beta\.kubernetes\.io\/azure-load-balancer-health-probe-request-path=/healthz' \
  --namespace projectcontour \
  --create-namespace
