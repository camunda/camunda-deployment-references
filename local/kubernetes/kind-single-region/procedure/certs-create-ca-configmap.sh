#!/bin/bash
set -euo pipefail

# Create ConfigMap with mkcert CA for pods that need to trust it

if ! command -v mkcert &> /dev/null; then
    echo "Error: mkcert is not installed."
    exit 1
fi

MKCERT_CA_ROOT="$(mkcert -CAROOT 2>/dev/null)"

if [[ ! -f "$MKCERT_CA_ROOT/rootCA.pem" ]]; then
    echo "Error: mkcert CA not found. Run mkcert -install first."
    exit 1
fi

echo "Creating CA ConfigMap 'mkcert-ca' in namespace 'camunda'..."

kubectl create configmap mkcert-ca \
    --from-file=ca.crt="$MKCERT_CA_ROOT/rootCA.pem" \
    --namespace=camunda \
    --dry-run=client -o yaml | kubectl apply -f -

echo "CA ConfigMap created"
