#!/bin/bash

# Private cluster (private_vpc = true): the public subnets still exist, so the load balancer is
# internet-facing by default. To keep it reachable only from the VPC (and its VPN), add:
#   --set-string 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-internal=true' \

helm upgrade --install \
  ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --version "$INGRESS_HELM_CHART_VERSION" \
  --set 'controller.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-backend-protocol=tcp' \
  --set 'controller.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-cross-zone-load-balancing-enabled=true' \
  --set 'controller.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-type=nlb' \
  --namespace ingress-nginx \
  --create-namespace
