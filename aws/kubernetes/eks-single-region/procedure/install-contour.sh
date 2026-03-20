#!/bin/bash

helm upgrade --install \
  contour contour \
  --repo https://charts.bitnami.com/bitnami \
  --version "$CONTOUR_HELM_CHART_VERSION" \
  --set 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-backend-protocol=tcp' \
  --set 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-cross-zone-load-balancing-enabled=true' \
  --set 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-type=nlb' \
  --namespace projectcontour \
  --create-namespace
