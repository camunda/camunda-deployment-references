#!/bin/bash

helm upgrade --install \
  contour contour \
  --repo https://charts.bitnami.com/bitnami \
  --version "$CONTOUR_HELM_CHART_VERSION" \
  --namespace projectcontour \
  --create-namespace \
  --set contour.replicaCount=2 \
  --set envoy.replicaCount=2 \
  --set envoy.service.externalTrafficPolicy=Local \
  --set 'envoy.service.annotations.service\.beta\.kubernetes\.io\/azure-load-balancer-health-probe-request-path'=/ready
