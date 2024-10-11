#!/bin/bash
set -o pipefail

source "$(dirname "$0")/helpers.sh"

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

echo "[INFO] Pulling information from the Terraform state file to configure the Camunda 8 environment or check preassigned values."

if [ -z "${IPS+x}" ]; then
    echo "[INFO] IPS was not overwritten via env vars... pulling from Terraform state file."
    IPS_JSON=$(terraform output -state "$(dirname "$0")/../terraform/terraform.tfstate" -json camunda_ips)
    cleaned_str=$(echo "${IPS_JSON}" | tr -d '[]"')
    read -r -a IPS <<< "$(echo "${cleaned_str}" | tr ',' ' ')"
fi

echo "[INFO] Detected following values for IPS: ${cleaned_str}"

if [ -z "${BASTION_IP+x}" ]; then
    echo "[INFO] BASTION_IP was not overwritten via env vars... pulling from Terraform state file."
    BASTION_IP=$(terraform output -state "$(dirname "$0")/../terraform/terraform.tfstate" -raw bastion_ip)
fi

echo "[INFO] Detected following values for the BASTION_IP: ${BASTION_IP}"

if [ -z "${OPENSEARCH_URL+x}" ]; then
    echo "[INFO] OPENSEARCH_URL was not overwritten via env vars... pulling from Terraform state file."
    OPENSEARCH_URL=$(terraform output -state "$(dirname "$0")/../terraform/terraform.tfstate" -raw aws_opensearch_domain)
fi

echo "[INFO] Detected following values for the OPENSEARCH_URL: ${OPENSEARCH_URL}"

if [ -z "${GRPC_ENDPOINT+x}" ]; then
    echo "[INFO] GRPC_ENDPOINT was not overwritten via env vars... pulling from Terraform state file."
    GRPC_ENDPOINT=$(terraform output -state "$(dirname "$0")/../terraform/terraform.tfstate" -raw nlb_endpoint)
fi

echo "[INFO] Detected following values for the GRPC_ENDPOINT: ${GRPC_ENDPOINT}"

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

    ssh -J "admin@${BASTION_IP}" "admin@${ip}" < "$(dirname "$0")/camunda-install.sh"

    echo "[INFO] Attempting to connect to ${ip} to configure the Camunda 8 environment."

    # Creates temporary dynamic config file
    source "$(dirname "$0")/camunda-configure.sh"

    if [[ $SECURITY == 'true' ]]; then
        source "$(dirname "$0")/camunda-security.sh"
    fi

    # Copy final config and enable all services
    source "$(dirname "$0")/camunda-services.sh"

    # Optionally install CloudWatch Agent
    if [[ $CLOUDWATCH_ENABLED == 'true' ]]; then
        ssh -J "admin@${BASTION_IP}" "admin@${ip}" < "$(dirname "$0")/cloudwatch-install.sh"
        source "$(dirname "$0")/cloudwatch-configure.sh"
    fi
done

for ip in "${IPS[@]}"; do
    echo "[INFO] Doing final checks on the Camunda 8 environment on ${ip}."
    ssh -J "admin@${BASTION_IP}" "admin@${ip}" < "$(dirname "$0")/camunda-checks.sh"
    code=$?
    if [[ "$code" -ne 0 ]]; then
        echo "[FAIL] The Camunda 8 environment on ${ip} is not healthy."
        exit 1
    fi
done
