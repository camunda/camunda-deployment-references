#!/bin/bash
set -o pipefail

CURRENT_DIR="$(dirname "$0")"

source "${CURRENT_DIR}/helpers.sh"

# Optional download-cache helpers. By default this is a no-op: every node downloads its own
# artifacts directly (see camunda-install.sh). Our CI sets CAMUNDA_DISTRO_CACHE_LIB to a small
# helper that downloads the distribution + connectors once and stages them on each node, so this
# reference procedure stays free of any CI/caching plumbing.
if [[ -n "${CAMUNDA_DISTRO_CACHE_LIB:-}" && -f "${CAMUNDA_DISTRO_CACHE_LIB}" ]]; then
    # shellcheck source=/dev/null
    source "${CAMUNDA_DISTRO_CACHE_LIB}"
fi

CLOUDWATCH_ENABLED=${CLOUDWATCH_ENABLED:-false}
USERNAME=${USERNAME:-"camunda"}
ADMIN_USERNAME=${ADMIN_USERNAME:-"ubuntu"}
MNT_DIR=${MNT_DIR:-"/opt/camunda"}
BROKER_PORT=${BROKER_PORT:-26502}
TERRAFORM_DIR=${TERRAFORM_DIR:-"${CURRENT_DIR}/../terraform/cluster"}

CAMUNDA_DISTRO_USER=${CAMUNDA_DISTRO_USER:-""}
CAMUNDA_DISTRO_PASSWORD=${CAMUNDA_DISTRO_PASSWORD:-""}

check_tool_installed "ssh"
check_tool_installed "openssl"
check_tool_installed "sftp"
check_tool_installed "terraform"

echo "[INFO] CloudWatch monitoring is set to: $CLOUDWATCH_ENABLED."

echo "[INFO] Pulling information from the Terraform state file to configure the Camunda 8 environment or check preassigned values."

if [ -z "${IPS+x}" ]; then
    echo "[INFO] IPS was not overwritten via env vars... pulling from Terraform state file."
    IPS_JSON=$(terraform -chdir="$TERRAFORM_DIR" output -json camunda_ips)
    cleaned_str=$(echo "${IPS_JSON}" | tr -d '[]"')
    read -r -a IPS <<< "$(echo "${cleaned_str}" | tr ',' ' ')"
else
    # IPS env var can be supplied as "IP1 IP2 IP3"
    read -r -a IPS <<< "${IPS[@]}"
fi

echo "[INFO] Detected following values for IPS: ${IPS[*]}"

if [ -z "${BASTION_IP+x}" ]; then
    echo "[INFO] BASTION_IP was not overwritten via env vars... pulling from Terraform state file."
    BASTION_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw bastion_ip)
fi

echo "[INFO] Detected following values for the BASTION_IP: ${BASTION_IP}"

if [ -z "${OPENSEARCH_URL+x}" ]; then
    echo "[INFO] OPENSEARCH_URL was not overwritten via env vars... pulling from Terraform state file."
    OPENSEARCH_URL=$(terraform -chdir="$TERRAFORM_DIR" output -raw aws_opensearch_domain)
fi

echo "[INFO] Detected following values for the OPENSEARCH_URL: ${OPENSEARCH_URL}"

if [ -z "${GRPC_ENDPOINT+x}" ]; then
    echo "[INFO] GRPC_ENDPOINT was not overwritten via env vars... pulling from Terraform state file."
    GRPC_ENDPOINT=$(terraform -chdir="$TERRAFORM_DIR" output -raw nlb_endpoint)
fi

echo "[INFO] Detected following values for the GRPC_ENDPOINT: ${GRPC_ENDPOINT}"

MNT_DIR="/opt/camunda"

ips_list=""

for ip in "${IPS[@]}"; do
    ips_list+="${ip}:${BROKER_PORT},"
done

ips_list=${ips_list%,}
total_ip_count=${#IPS[@]}

# Optionally pre-download the artifacts once for all nodes (no-op unless the cache helper above is
# loaded, i.e. in CI).
if declare -F warm_distro_cache >/dev/null; then
    warm_distro_cache
fi

# Loop over each IP address
# We're using source to call up child scripts with the same variable context
# The idea is to divide the logic into smaller scripts for better readability and maintainability
for index in "${!IPS[@]}"; do
    ip=${IPS[$index]}

    # Write credentials to a temp file on the remote host via stdin to avoid
    # leaking them in process listings or CI logs. The install script reads and
    # deletes this file. A separate SSH call is used so that the install script's
    # stdin remains clean (the script uses a heredoc internally).
    if [[ -n "${CAMUNDA_DISTRO_USER}" && -n "${CAMUNDA_DISTRO_PASSWORD}" ]]; then
        printf '%s\n%s\n' "${CAMUNDA_DISTRO_USER}" "${CAMUNDA_DISTRO_PASSWORD}" | \
            ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" \
            'cat > /tmp/.camunda-distro-credentials && chmod 600 /tmp/.camunda-distro-credentials'
    fi

    # Optionally stage the pre-downloaded artifacts on this node (no-op unless the cache helper is
    # loaded). The install script then copies them instead of downloading.
    if declare -F push_distro_cache_to_node >/dev/null; then
        push_distro_cache_to_node "${ip}"
    fi

    # Pipe the install script to the node. When the optional cache helper is loaded it prepends an
    # opt-in export so the node consults the staged artifacts; otherwise only the script is sent and
    # the node downloads from Artifactory as usual.
    {
        if declare -F distro_install_prelude >/dev/null; then
            distro_install_prelude
        fi
        cat "${CURRENT_DIR}/camunda-install.sh"
    } | ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}"

    echo "[INFO] Attempting to connect to ${ip} to configure the Camunda 8 environment."

    # Creates temporary dynamic config file
    source "${CURRENT_DIR}/camunda-configure.sh"

    # Copy final config and enable all services
    source "${CURRENT_DIR}/camunda-services.sh"

    # Optionally install CloudWatch Agent
    if [[ $CLOUDWATCH_ENABLED == 'true' ]]; then
        ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" < "${CURRENT_DIR}/cloudwatch-install.sh"
        source "${CURRENT_DIR}/cloudwatch-configure.sh"
    fi
done

for ip in "${IPS[@]}"; do
    echo "[INFO] Doing final checks on the Camunda 8 environment on ${ip}."
    ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" < "${CURRENT_DIR}/camunda-checks.sh"
    code=$?
    if [[ "$code" -ne 0 ]]; then
        echo "[FAIL] The Camunda 8 environment on ${ip} is not healthy."
        exit 1
    fi
done
