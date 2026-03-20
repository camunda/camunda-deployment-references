#!/bin/bash

helm repo add contour https://projectcontour.github.io/helm-charts/
helm upgrade --install contour contour/contour \
  --version "$CONTOUR_HELM_CHART_VERSION" \
  --namespace projectcontour \
  --create-namespace \
  --set contour.replicas=2 \
  --set envoy.service.externalTrafficPolicy=Local \
  --set envoy.service.annotations."service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"=/healthz
