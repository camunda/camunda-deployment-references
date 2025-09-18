#!/bin/bash
set -euo pipefail

# This script creates the base config for the Camunda 8 environment.
# Some values are not static and can only be determined with an existing infrastructure.
# The idea is that the script is run per Camunda instance and the environment variables are set accordingly.
# If not, the main value that differs between each instance is the IP address and most importantly the node ID.
# Important the node ID has to be unique and each machine must always be started with the same node ID afterwards.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../configs"

echo "[INFO] Validating required environment variables..."

if [ -z "${total_ip_count:-}" ]; then
    echo "[ERROR] Variable 'total_ip_count' is not defined."
    echo "        This should be the total number of Camunda instances in the cluster."
    echo "        Example: export total_ip_count=3"
    exit 1
fi

if [ -z "${ips_list:-}" ]; then
    echo "[ERROR] Variable 'ips_list' is not defined."
    echo "        This should be a comma-separated list of all Camunda instance IPs with the communication port."
    echo "        Example: export ips_list='10.0.1.10:26502,10.0.1.11:26502,10.0.1.12:26502'"
    exit 1
fi

if [ -z "${index:-}" ]; then
    echo "[ERROR] Variable 'index' is not defined."
    echo "        This should be the unique node ID for this instance (0-based)."
    echo "        It's incremental and each machine must always be started with the same node ID afterwards."
    echo "        Example: export index=0"
    exit 1
fi

if [ -z "${ip:-}" ]; then
    echo "[ERROR] Variable 'ip' is not defined."
    echo "        This should be the IP address of this specific instance."
    echo "        Example: export ip='10.0.1.10'"
    exit 1
fi

if [ -z "${OPENSEARCH_URL:-}" ]; then
    echo "[ERROR] Variable 'OPENSEARCH_URL' is not defined."
    echo "        This should be the full URL to your OpenSearch cluster."
    echo "        Example: export OPENSEARCH_URL='https://vpc-camunda-abc123.us-east-1.es.amazonaws.com:443'"
    exit 1
fi

echo "[INFO] All required variables are defined. Proceeding with configuration..."

echo "[INFO] Copying existing configuration files to temporary files for modification..."

cp "${CONFIG_DIR}/camunda-environment" "${SCRIPT_DIR}/camunda-environment.tmp"
cp "${CONFIG_DIR}/connectors-environment" "${SCRIPT_DIR}/connectors-environment.tmp"

echo "[INFO] Configuring the environment variables for cluster communication, external DB usage and writing to temporary camunda-environment file."
# Default configuration for setup with OpenSearch as DB
{
    # Broker Setup
    echo "CAMUNDA_CLUSTER_NODEID=\"${index}\""
    echo "CAMUNDA_CLUSTER_SIZE=\"${total_ip_count}\""
    echo "CAMUNDA_CLUSTER_REPLICATIONFACTOR=\"${total_ip_count}\""
    echo "ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS=\"${ips_list}\""
    echo "ZEEBE_BROKER_NETWORK_ADVERTISEDHOST=\"${ip}\""
    # External DB setup
    echo "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_URL=\"${OPENSEARCH_URL}\""
} >> "${SCRIPT_DIR}/camunda-environment.tmp"
