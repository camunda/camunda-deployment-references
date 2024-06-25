#!/bin/bash

# Enable secure cluster communication
SECURITY=${SECURITY:-true}

echo "Secure cluster communication is set to: $SECURITY."

if [[ $SECURITY == 'true' ]]; then
    echo "Checking that the CA certificate files are present in the current directory."
    if [ ! -f "ca-authority.pem" ]; then
        echo "Error: CA certificate file 'ca-authority.pem' not found in this path."
        echo "Please run the 'generate-self-signed-cert-authority.sh' script to generate the CA certificate."
        echo "Make sure to keep the certificates secure for future script runs."
        echo "Alternatively set the SECURITY environment variable to 'false' to disable secure communication."
        exit 1
    fi

    if [ ! -f "ca-authority.key" ]; then
        echo "Error: CA certificate file 'ca-authority.key' not found in this path."
        echo "Please run the 'generate-self-signed-cert-authority.sh' script to generate the CA certificate."
        echo "Make sure to keep the certificates secure for future script runs."
        echo "Alternatively set the SECURITY environment variable to 'false' to disable secure communication."
        exit 1
    fi
fi

echo "Pulling information from the Terraform state file to configure the Camunda 8 environment."
IPS_JSON=$(terraform output -state ../terraform/terraform.tfstate -json camunda_ips)
cleaned_str=$(echo "${IPS_JSON}" | tr -d '[]"')
read -r -a IPS <<< "$(echo "${cleaned_str}" | tr ',' ' ')"

BASTION_IP=$(terraform output -state ../terraform/terraform.tfstate -raw bastion_ip)
BROKER_PORT=26502

OPENSEARCH_URL=$(terraform output -state ../terraform/terraform.tfstate -raw aws_opensearch_domain)
GRPC_ENDPOINT=$(terraform output -state ../terraform/terraform.tfstate -raw nlb_endpoint)

if [ -z "$OPENSEARCH_URL" ]; then
    echo "No value found for OPENSEARCH_URL in the Terraform state file."
    echo "Trying to overwrite the OPENSEARCH_URL with the equivalent environment variable."
    OPENSEARCH_URL=${OPENSEARCH_URL:-""}
fi

if [ -z "$GRPC_ENDPOINT" ]; then
    echo "No value found for GRPC_ENDPOINT in the Terraform state file."
    echo "Trying to overwrite the GRPC_ENDPOINT with the equivalent environment variable."
    GRPC_ENDPOINT=${GRPC_ENDPOINT:-""}
fi

MNT_DIR="/camunda"

ips_list=""

for ip in "${IPS[@]}"; do
    ips_list+="${ip}:${BROKER_PORT},"
done

ips_list=${ips_list%,}
total_ip_count=${#IPS[@]}

# Loop over each IP address
for index in "${!IPS[@]}"; do
    ip=${IPS[$index]}

    ssh -J "admin@${BASTION_IP}" "admin@${ip}" < camunda-install.sh

    echo "Attempting to connect to ${ip} to configure the Camunda 8 environment."

    cp camunda-environment camunda-environment.tmp

    echo "Configuring the environment variables for cluster communication, external DB usage and writing to temporary camunda-environment file."
    # Default configuration for 3 HA setup with OpenSearch as DB
    {
        echo "ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS=\"${ips_list}\""
        echo "ZEEBE_BROKER_CLUSTER_NODEID=\"${index}\""
        echo "ZEEBE_BROKER_NETWORK_ADVERTISEDHOST=\"${ip}\""
        echo "CAMUNDA_OPERATE_OPENSEARCH_URL=\"${OPENSEARCH_URL}\""
        echo "CAMUNDA_OPERATE_ZEEBEOPENSEARCH_URL=\"${OPENSEARCH_URL}\""
        echo "CAMUNDA_TASKLIST_OPENSEARCH_URL=\"${OPENSEARCH_URL}\""
        echo "CAMUNDA_TASKLIST_ZEEBEOPENSEARCH_URL=\"${OPENSEARCH_URL}\""
        echo "ZEEBE_BROKER_EXPORTERS_OPENSEARCH_ARGS_URL=\"${OPENSEARCH_URL}\""
    } >> camunda-environment.tmp

    # Disabling problematic importers and archivers in Operate and Tasklist
    # These are not HA compatbile and can only run once but we keep the WebUI

    # if index is even and total count is more than 1 or index is greater than 2
    # disable exporters for those instances
    # essentially we just want to keep the exporter on the first uneven instance
    # While keeping it flexible to use different amount of nodes.
    if (( index % 2 == 0 && total_ip_count > 1 )) || (( index > 2 )); then
        {
            echo "CAMUNDA_OPERATE_IMPORTERENABLED=\"false\""
            echo "CAMUNDA_OPERATE_ARCHIVERENABLED=\"false\""
            echo "CAMUNDA_TASKLIST_IMPORTERENABLED=\"false\""
            echo "CAMUNDA_TASKLIST_ARCHIVERENABLED=\"false\""
        } >> camunda-environment.tmp
    fi

    if [[ $SECURITY == 'true' ]]; then
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
    fi

    echo "Copying the configuration files to the remote server."
    scp -o "ProxyJump=admin@${BASTION_IP}" camunda-environment.tmp "admin@${ip}:${MNT_DIR}/camunda/config/camunda-environment"
    rm -rf camunda-environment.tmp

    scp -o "ProxyJump=admin@${BASTION_IP}" connectors-environment "admin@${ip}:${MNT_DIR}/connectors/"

    echo "Installing the Camunda 8 systemd service on the remote server."
    scp -o "ProxyJump=admin@${BASTION_IP}" camunda.service "admin@${ip}:${MNT_DIR}"
    scp -o "ProxyJump=admin@${BASTION_IP}" connectors.service "admin@${ip}:${MNT_DIR}"


    ssh -J "admin@${BASTION_IP}" "admin@${ip}" "sudo mv ${MNT_DIR}/camunda.service /etc/systemd/system/camunda.service"
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" "sudo mv ${MNT_DIR}/connectors.service /etc/systemd/system/connectors.service"
    # Install and activate Camunda 8 Service
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl daemon-reload'
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl enable camunda.service'
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl start camunda.service'
    # restarting the service in case the script is called twice with config changes
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl restart camunda.service'

    # Install and activate Connectors Service
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl enable connectors.service'
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl start connectors.service'
    # restarting the service in case the script is called twice with config changes
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl restart connectors.service'
done
