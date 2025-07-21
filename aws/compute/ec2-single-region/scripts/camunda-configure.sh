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
    echo "ZEEBE_BROKER_CLUSTER_PARTITIONSCOUNT=\"${total_ip_count}\""
    echo "ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS=\"${ips_list}\""
    echo "ZEEBE_BROKER_CLUSTER_NODEID=\"${index}\""
    echo "ZEEBE_BROKER_NETWORK_ADVERTISEDHOST=\"${ip}\""
    # External DB setup
    echo "CAMUNDA_OPERATE_OPENSEARCH_URL=\"${OPENSEARCH_URL}\""
    echo "CAMUNDA_OPERATE_ZEEBEOPENSEARCH_URL=\"${OPENSEARCH_URL}\""
    echo "CAMUNDA_TASKLIST_OPENSEARCH_URL=\"${OPENSEARCH_URL}\""
    echo "CAMUNDA_TASKLIST_ZEEBEOPENSEARCH_URL=\"${OPENSEARCH_URL}\""
    echo "ZEEBE_BROKER_EXPORTERS_CAMUNDAEXPORTER_ARGS_CONNECT_URL=\"${OPENSEARCH_URL}\""
    echo "CAMUNDA_DATABASE_URL=\"${OPENSEARCH_URL}\""
    # Disable old importers
    echo "CAMUNDA_OPERATE_IMPORTERENABLED=\"false\""
    echo "CAMUNDA_OPERATE_ARCHIVERENABLED=\"false\""
    echo "CAMUNDA_TASKLIST_IMPORTERENABLED=\"false\""
    echo "CAMUNDA_TASKLIST_ARCHIVERENABLED=\"false\""
} >> "${CURRENT_DIR}/camunda-environment.tmp"

if [[ $SECURITY == 'false' ]]; then
  echo "[INFO] Configuring Connectors to use plain text communication."
  {
    echo "ZEEBE_CLIENT_SECURITY_PLAINTEXT=\"true\""
  } >> "${CURRENT_DIR}/connectors-environment.tmp"
fi
