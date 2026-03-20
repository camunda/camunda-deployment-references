#!/bin/bash

# The domain name you intend to use
export CAMUNDA_DOMAIN=camunda.example.com
# The email address for Let's Encrypt registration
export MAIL=admin@camunda.example.com
# Helm chart versions for Ingress components

# renovate: datasource=helm depName=contour registryUrl=https://charts.bitnami.com/bitnami
export CONTOUR_HELM_CHART_VERSION="21.1.4"
# renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
export EXTERNAL_DNS_HELM_CHART_VERSION="1.20.0"
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
export CERT_MANAGER_HELM_CHART_VERSION="1.20.0"
