#!/bin/bash
set -euo pipefail

# Create TLS secret in Kubernetes from mkcert certificates

if [[ ! -f ".certs/tls.crt" ]] || [[ ! -f ".certs/tls.key" ]]; then
    echo "Error: Certificates not found in .certs/"
    echo "Run ./certs-generate.sh first"
    exit 1
fi

echo "Creating TLS secret 'camunda-platform' in namespace 'camunda'..."

kubectl create secret tls camunda-platform \
    --cert=".certs/tls.crt" \
    --key=".certs/tls.key" \
    --namespace=camunda \
    --dry-run=client -o yaml | kubectl apply -f -

echo "TLS secret created"
