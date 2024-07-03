#!/bin/bash
set -euo pipefail

source ./helpers.sh

# Optional feature, disabled by default and can be overwrittne witht the env var "SECURITY"
# This script configures Camunda 8 to use TLS for secure communication between the brokers and the gateway.

TMP_CERTS_DIR="./tmp-certs"

# Configure secure communication via self-signed certificates
echo "[INFO] Generating certificates for broker/broker and broker/gateway communication."
mkdir -p "${TMP_CERTS_DIR}"
./generate-self-signed-cert-node.sh "${index}" "${index}" "${ip}" "${TMP_CERTS_DIR}"

transfer_file "${TMP_CERTS_DIR}/${index}-chain.pem" "${MNT_DIR}/camunda/config/" "${index}-chain.pem"
transfer_file "${TMP_CERTS_DIR}/${index}.key" "${MNT_DIR}/camunda/config/" "${index}.key"

if [ -n "$GRPC_ENDPOINT" ]; then
    echo "[INFO] Generating certificates for gateway/client communication."
    ./generate-self-signed-cert-node.sh gateway $((index + total_ip_count)) 127.0.0.1 "${TMP_CERTS_DIR}" "${GRPC_ENDPOINT}"
    transfer_file "${TMP_CERTS_DIR}/gateway-chain.pem" "${MNT_DIR}/camunda/config/" "gateway-chain.pem"
    transfer_file "${TMP_CERTS_DIR}/gateway.key" "${MNT_DIR}/camunda/config/" "gateway.key"
fi

rm -rf "${TMP_CERTS_DIR}"

echo "[INFO] Configuring the environment variables for secure communication and writing to temporary camunda-environment file."
{
    # Broker to Broker communication (including embedded Gateway)
    echo "ZEEBE_BROKER_NETWORK_SECURITY_ENABLED=\"true\""
    echo "ZEEBE_BROKER_NETWORK_SECURITY_CERTIFICATECHAINPATH=\"${MNT_DIR}/camunda/config/$index-chain.pem\""
    echo "ZEEBE_BROKER_NETWORK_SECURITY_PRIVATEKEYPATH=\"${MNT_DIR}/camunda/config/$index.key\""

    # Gateway to Client communication
    if [ -n "$GRPC_ENDPOINT" ]; then
        echo "ZEEBE_BROKER_GATEWAY_SECURITY_ENABLED=\"true\""
        echo "ZEEBE_BROKER_GATEWAY_SECURITY_CERTIFICATECHAINPATH=\"${MNT_DIR}/camunda/config/gateway-chain.pem\""
        echo "ZEEBE_BROKER_GATEWAY_SECURITY_PRIVATEKEYPATH=\"${MNT_DIR}/camunda/config/gateway.key\""
    fi
} >> camunda-environment.tmp
