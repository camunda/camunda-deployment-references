#!/bin/bash
# Create secrets for Web Modeler configuration:
# - webmodeler-secret: SMTP password for email delivery
#
# Note: WebModeler PostgreSQL is now managed by the CNPG operator.
# Database secrets are created by generic/kubernetes/operator-based/postgresql/set-secrets.sh

set -euo pipefail

# Modify this value to set your SMTP password
SMTP_PASSWORD="${SMTP_PASSWORD:-}"

oc create secret generic webmodeler-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=smtp-password="$SMTP_PASSWORD" \
  --dry-run=client -o yaml | oc apply -f -
