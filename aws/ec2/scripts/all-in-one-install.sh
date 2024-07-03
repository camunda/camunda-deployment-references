#!/bin/bash
set -o pipefail

source ./helpers.sh

# Enable secure cluster communication
SECURITY=${SECURITY:-false}
CLOUDWATCH_ENABLED=${CLOUDWATCH_ENABLED:-false}
USERNAME=${USERNAME:-"camunda"}
MNT_DIR=${MNT_DIR:-"/opt/camunda"}
BROKER_PORT=${BROKER_PORT:-26502}

check_tool_installed "ssh"
check_tool_installed "openssl"
check_tool_installed "sftp"
check_tool_installed "terraform"

echo "[INFO] Secure cluster communication is set to: $SECURITY."
echo "[INFO] CloudWatch monitoring is set to: $CLOUDWATCH_ENABLED."

if [[ $SECURITY == 'true' ]]; then
    echo "[INFO] Checking that the CA certificate files are present in the current directory."
    if [ ! -f "ca-authority.pem" ]; then
        echo "[FAIL] Error: CA certificate file 'ca-authority.pem' not found in this path."
        echo "Please run the 'generate-self-signed-cert-authority.sh' script to generate the CA certificate."
        echo "Make sure to keep the certificates secure for future script runs."
        echo "Alternatively set the SECURITY environment variable to 'false' to disable secure communication."
        exit 1
    fi

    if [ ! -f "ca-authority.key" ]; then
        echo "[FAIL] Error: CA certificate file 'ca-authority.key' not found in this path."
        echo "Please run the 'generate-self-signed-cert-authority.sh' script to generate the CA certificate."
        echo "Make sure to keep the certificates secure for future script runs."
        echo "Alternatively set the SECURITY environment variable to 'false' to disable secure communication."
        exit 1
    fi
fi

echo "[INFO] Pulling information from the Terraform state file to configure the Camunda 8 environment."
IPS_JSON=$(terraform output -state ../terraform/terraform.tfstate -json camunda_ips)
cleaned_str=$(echo "${IPS_JSON}" | tr -d '[]"')
read -r -a IPS <<< "$(echo "${cleaned_str}" | tr ',' ' ')"

BASTION_IP=$(terraform output -state ../terraform/terraform.tfstate -raw bastion_ip)

OPENSEARCH_URL=$(terraform output -state ../terraform/terraform.tfstate -raw aws_opensearch_domain)
GRPC_ENDPOINT=$(terraform output -state ../terraform/terraform.tfstate -raw nlb_endpoint)

if [ -z "$OPENSEARCH_URL" ]; then
    echo "[INFO] No value found for OPENSEARCH_URL in the Terraform state file."
    echo "[INFO] Trying to overwrite the OPENSEARCH_URL with the equivalent environment variable."
    OPENSEARCH_URL=${OPENSEARCH_URL:-""}
fi

if [ -z "$GRPC_ENDPOINT" ]; then
    echo "[INFO] No value found for GRPC_ENDPOINT in the Terraform state file."
    echo "[INFO] Trying to overwrite the GRPC_ENDPOINT with the equivalent environment variable."
    GRPC_ENDPOINT=${GRPC_ENDPOINT:-""}
fi

MNT_DIR="/opt/camunda"

ips_list=""

for ip in "${IPS[@]}"; do
    ips_list+="${ip}:${BROKER_PORT},"
done

ips_list=${ips_list%,}
total_ip_count=${#IPS[@]}

# Loop over each IP address
# We're using source to call up child scripts with the same variable context
# The idea is to divide the logic into smaller scripts for better readability and maintainability
for index in "${!IPS[@]}"; do
    ip=${IPS[$index]}

    ssh -J "admin@${BASTION_IP}" "admin@${ip}" < camunda-install.sh

    echo "[INFO] Attempting to connect to ${ip} to configure the Camunda 8 environment."

    # Creates temporary dynamic config file
    source camunda-configure.sh

    if [[ $SECURITY == 'true' ]]; then
        source camunda-security.sh
    fi

    # Copy final config and enable all services
    source camunda-services.sh

    # Optionally install CloudWatch Agent
    if [[ $CLOUDWATCH_ENABLED == 'true' ]]; then
        ssh -J "admin@${BASTION_IP}" "admin@${ip}" < cloudwatch-install.sh
        source cloudwatch-configure.sh
    fi
done

for ip in "${IPS[@]}"; do
    echo "[INFO] Doing final checks on the Camunda 8 environment on ${ip}."
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" < camunda-checks.sh
    code=$?
    if [[ "$code" -ne 0 ]]; then
        echo "[FAIL] The Camunda 8 environment on ${ip} is not healthy."
        exit 1
    fi
done
