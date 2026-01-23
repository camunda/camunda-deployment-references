#!/bin/bash
# Create the webmodeler-postgres-secret for Web Modeler database
# In IRSA mode, this is a placeholder (empty password) because IAM authentication is used

set -euo pipefail

kubectl create secret generic webmodeler-postgres-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=password="" \
  --dry-run=client -o yaml | kubectl apply -f -
