#!/bin/bash

helm repo add contour https://projectcontour.github.io/helm-charts/
helm upgrade --install contour contour/contour \
  --namespace projectcontour \
  --create-namespace \
  --set envoy.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-backend-protocol"=tcp \
  --set envoy.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"=true \
  --set envoy.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb
