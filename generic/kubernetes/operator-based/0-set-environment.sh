#!/bin/bash

# Set environment variables for Camunda operator-based deployment
# Source this file to set the required environment variables

# Camunda namespace
export CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"

# Domain configuration
export CAMUNDA_DOMAIN="${CAMUNDA_DOMAIN:-localhost}"
export CAMUNDA_PROTOCOL="${CAMUNDA_PROTOCOL:-http}"

# Helm chart configuration
export CAMUNDA_HELM_CHART_VERSION="${CAMUNDA_HELM_CHART_VERSION:-0.0.0-snapshot-alpha}"

echo "Environment variables set:"
echo "  CAMUNDA_NAMESPACE=$CAMUNDA_NAMESPACE"
echo "  CAMUNDA_DOMAIN=$CAMUNDA_DOMAIN"
echo "  CAMUNDA_PROTOCOL=$CAMUNDA_PROTOCOL"
echo "  CAMUNDA_HELM_CHART_VERSION=$CAMUNDA_HELM_CHART_VERSION"
echo ""
