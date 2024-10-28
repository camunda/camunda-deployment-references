#!/bin/bash
set -euo pipefail

# This script creates the dynamic config for the Camunda 8 environment.
# This includes the Zeebe cluster configuration but also disabling non HA compatible features in Operate and Tasklist.

cp "${CURRENT_DIR}/../configs/camunda-environment" "${CURRENT_DIR}/camunda-environment.tmp"
cp "${CURRENT_DIR}/../configs/connectors-environment" "${CURRENT_DIR}/connectors-environment.tmp"

echo "[INFO] Configuring the environment variables for cluster communication, external DB usage and writing to temporary camunda-environment file."
# Default configuration for 3 HA setup with OpenSearch as DB
{
    # Broker Setup
    echo "ZEEBE_BROKER_CLUSTER_CLUSTERSIZE=\"${total_ip_count}\""
    echo "ZEEBE_BROKER_CLUSTER_REPLICATIONFACTOR=\"${total_ip_count}\""
    echo "ZEEBE_BROKER_CLUSTER_PARTITIONSCOUNT=\"$((total_ip_count + 1))\""
    echo "ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS=\"${ips_list}\""
    echo "ZEEBE_BROKER_CLUSTER_NODEID=\"${index}\""
    echo "ZEEBE_BROKER_NETWORK_ADVERTISEDHOST=\"${ip}\""
    # External DB setup
    echo "CAMUNDA_OPERATE_OPENSEARCH_URL=\"${OPENSEARCH_URL}\""
    echo "CAMUNDA_OPERATE_ZEEBEOPENSEARCH_URL=\"${OPENSEARCH_URL}\""
    echo "CAMUNDA_TASKLIST_OPENSEARCH_URL=\"${OPENSEARCH_URL}\""
    echo "CAMUNDA_TASKLIST_ZEEBEOPENSEARCH_URL=\"${OPENSEARCH_URL}\""
    echo "ZEEBE_BROKER_EXPORTERS_OPENSEARCH_ARGS_URL=\"${OPENSEARCH_URL}\""
} >> "${CURRENT_DIR}/camunda-environment.tmp"

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
  } >> "${CURRENT_DIR}/camunda-environment.tmp"
fi

if [[ $SECURITY == 'false' ]]; then
  echo "[INFO] Configuring Connectors to use plain text communication."
  {
    echo "ZEEBE_CLIENT_SECURITY_PLAINTEXT=\"true\""
  } >> "${CURRENT_DIR}/connectors-environment.tmp"
fi
