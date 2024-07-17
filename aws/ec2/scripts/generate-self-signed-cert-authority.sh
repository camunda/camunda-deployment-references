#!/bin/bash
set -euo pipefail

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
  -keyout ca-authority.key \
  -out ca-authority.pem
