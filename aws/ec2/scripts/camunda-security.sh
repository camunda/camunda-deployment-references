#!/bin/bash

# Optional feature, disabled by default and can be overwrittne witht the env var "SECURITY"
# This script configures Camunda 8 to use TLS for secure communication between the brokers and the gateway.

# Configure secure communication via self-signed certificates
echo "Generating certificates for broker/broker and broker/gateway communication."
./generate-self-signed-cert-node.sh "${index}" "${index}" "${ip}"
scp -o "ProxyJump=admin@${BASTION_IP}" "$index-chain.pem" "admin@${ip}:${MNT_DIR}/camunda/config/"
scp -o "ProxyJump=admin@${BASTION_IP}" "$index.key" "admin@${ip}:${MNT_DIR}/camunda/config/"

if [ -n "$GRPC_ENDPOINT" ]; then
    echo "Generating certificates for gateway/client communication."
    ./generate-self-signed-cert-node.sh gateway $((index + total_ip_count)) 127.0.0.1 "$GRPC_ENDPOINT"
    scp -o "ProxyJump=admin@${BASTION_IP}" "gateway-chain.pem" "admin@${ip}:${MNT_DIR}/camunda/config/"
    scp -o "ProxyJump=admin@${BASTION_IP}" "gateway.key" "admin@${ip}:${MNT_DIR}/camunda/config/"
fi

echo "Configuring the environment variables for secure communication and writing to temporary camunda-environment file."
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

# Certificate Cleanup
rm -rf "$index-chain.pem"
rm -rf "$index.csr"
rm -rf "$index.pem"
rm -rf "$index.key"
rm -rf gateway-chain.pem
rm -rf gateway.csr
rm -rf gateway.pem
rm -rf gateway.key
