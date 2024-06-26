#!/bin/bash

# This script is intended to generate self-signed certificates for secure communication between the brokers and the gateway.
# It requires the previous creation of a certificate authority (CA) to sign the certificates.
# Can be used for broker/broker and gateway/client communication.

# Check if the number of arguments is 3 or 4
# 3 intended for broker/broker broker/gateway communication
# 4 intended for gateway/client communication
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <file_name> <index> <ip> [<dns>]"
  exit 1
fi

# Assign the inputs to variables
file_name=$1
index=$2
ip=$3
dns=$4 # optional for e.g. gateway cert
extra=""

if [ -n "$dns" ]; then
  extra=",DNS:$dns"
fi

# Generate private key
openssl genpkey -out "$file_name.key" -algorithm RSA -pkeyopt rsa_keygen_bits:4096

# Create a certificate signing request
openssl req -new -key "$file_name.key" -out "$file_name.csr" -batch

# Create certificate signed by the certificate authority
openssl x509 \
  -req \
  -days 3650 \
  -in "$file_name.csr" \
  -CA ca-authority.pem \
  -CAkey ca-authority.key \
  -set_serial "$index" \
  -extfile <(printf "subjectAltName = IP.1:%s%s" "$ip" "$extra") \
  -out "$file_name.pem"

# Create final certificate chain to allow verification
cat "$file_name.pem" ca-authority.pem > "$file_name-chain.pem"
