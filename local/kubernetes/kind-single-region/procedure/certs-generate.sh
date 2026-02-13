#!/bin/bash
set -euo pipefail

# Generate TLS certificates using mkcert for camunda.example.com

if ! command -v mkcert &> /dev/null; then
    echo "Error: mkcert is not installed."
    echo "Install: brew install mkcert (macOS) or see https://github.com/FiloSottile/mkcert"
    exit 1
fi

mkcert -install 2>/dev/null || true

echo "Generating TLS certificates for camunda.example.com..."

mkdir -p .certs

mkcert \
    -cert-file .certs/tls.crt \
    -key-file .certs/tls.key \
    "camunda.example.com" "*.camunda.example.com" "zeebe-camunda.example.com"

echo "Certificates generated in .certs/"
