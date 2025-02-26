#!/bin/bash
set -euo pipefail

CURRENT_DIR="$(dirname "$0")"

# The following is meant for demonstration purposes only and should not be used in production with the default self-signed certificates.
# Please conduct the Documentation - https://docs.camunda.io/docs/self-managed/zeebe-deployment/security/secure-client-communication/

# This script is intended to generate self-signed certificates for secure communication between the brokers and the gateway.
# It requires the previous creation of a certificate authority (CA) to sign the certificates.
# Can be used for broker/broker and gateway/client communication.

# Check if the number of arguments is 4 or 5
# 4 intended for broker/broker broker/gateway communication
# 5 intended for gateway/client communication
if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
  echo "Usage: $0 <file_name> <index> <ip> <output_dir> [<dns>]"
  exit 1
fi

# Assign the inputs to variables
file_name=$1
index=$2
ip=$3
output_dir=$4
dns=$5 # optional for e.g. gateway cert
extra=""

if [ -n "$dns" ]; then
  extra=",DNS:$dns"
fi

# Generate private key
openssl genpkey -out "$output_dir/$file_name.key" -algorithm RSA -pkeyopt rsa_keygen_bits:4096

# Create a certificate signing request
openssl req -new -key "$output_dir/$file_name.key" -out "$output_dir/$file_name.csr" -batch

# Create certificate signed by the certificate authority
openssl x509 \
  -req \
  -days 3650 \
  -in "$output_dir/$file_name.csr" \
  -CA "${CURRENT_DIR}/ca-authority.pem" \
  -CAkey "${CURRENT_DIR}/ca-authority.key" \
  -set_serial "$index" \
  -extfile <(printf "subjectAltName = IP.1:%s%s" "$ip" "$extra") \
  -out "$output_dir/$file_name.pem"

# Create final certificate chain to allow verification
cat "$output_dir/$file_name.pem" "${CURRENT_DIR}/ca-authority.pem" > "$output_dir/$file_name-chain.pem"
