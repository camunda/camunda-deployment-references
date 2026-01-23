#!/bin/bash
# Create the webmodeler-secret for Web Modeler configuration
# This secret contains only the SMTP password

set -euo pipefail

# Modify this value to set your SMTP password
SMTP_PASSWORD="${SMTP_PASSWORD:-}"

kubectl create secret generic webmodeler-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=smtp-password="$SMTP_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
