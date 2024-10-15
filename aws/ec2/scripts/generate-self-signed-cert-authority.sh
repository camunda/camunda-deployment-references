#!/bin/bash
set -euo pipefail

# The following is meant for demonstration purposes only and should not be used in production with the default self-signed certificates.
# Please conduct the Documentation - https://docs.camunda.io/docs/self-managed/zeebe-deployment/security/secure-client-communication/

# Creates a certificate authority (CA) that can be used to secure the cluster communication.

# Generate a self-signed certificate authority for the domain cluster.local
openssl req \
  -config <(printf "[req]\ndistinguished_name=dn\n[dn]\n[ext]\nbasicConstraints=CA:TRUE,pathlen:0") \
  -new \
  -newkey rsa:4096 \
  -nodes \
  -x509 \
  -subj "/C=DE/O=Test/OU=Test/ST=BE/CN=cluster.local" \
  -extensions ext \
  -keyout "$(dirname "$0")/ca-authority.key" \
  -out "$(dirname "$0")/ca-authority.pem"
