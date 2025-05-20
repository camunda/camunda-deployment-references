#!/bin/bash

helm upgrade --install \
  ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --version "$INGRESS_HELM_CHART_VERSION" \
  --namespace ingress-nginx \
  --create-namespace
