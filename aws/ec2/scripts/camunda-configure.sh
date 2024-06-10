#!/bin/bash

IPS_JSON=$(terraform output -state ../terraform/terraform.tfstate -json camunda_ips)
cleaned_str=$(echo "${IPS_JSON}" | tr -d '[]"')
read -r -a IPS <<< "$(echo "${cleaned_str}" | tr ',' ' ')"
#IPS=($(echo "${cleaned_str}" | tr ',' ' '))

BASTION_IP=$(terraform output -state ../terraform/terraform.tfstate -raw bastion_ip)
BROKER_PORT=26502

OPENSEARCH_URL=$(terraform output -state ../terraform/terraform.tfstate -raw aws_opensearch_domain)

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

    ssh -A -J "admin@${BASTION_IP}" "admin@${ip}" < camunda-install.sh

    echo "Attempting to connect to ${ip}"
    scp -o "ProxyJump=admin@${BASTION_IP}" camunda.service "admin@${ip}:${MNT_DIR}"

    ssh -A -J "admin@${BASTION_IP}" "admin@${ip}" "sudo mv ${MNT_DIR}/camunda.service /etc/systemd/system/camunda.service"

    cp camunda-environment camunda-environment.tmp

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

    scp -o "ProxyJump=admin@${BASTION_IP}" camunda-environment.tmp "admin@${ip}:${MNT_DIR}/camunda/config/camunda-environment"
    rm -rf camunda-environment.tmp

    ssh -A -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl daemon-reload'
    ssh -A -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl enable camunda.service'
    ssh -A -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl start camunda.service'
    # restarting the service in case the script is called twice with config changes
    ssh -A -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl restart camunda.service'
done
