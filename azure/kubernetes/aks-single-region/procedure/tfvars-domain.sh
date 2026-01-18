#!/bin/bash

export AZURE_SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)

export AZURE_DNS_ZONE_ID=$(az network dns zone show \
  --name "$TLD" \
  --resource-group "$AZURE_DNS_RESOURCE_GROUP" \
  --query "id" -o tsv)

# Generate domain name from cluster name and TLD
export DOMAIN_NAME="${CLUSTER_NAME}.${TLD}"

cat <<EOF > terraform.tfvars
subscription_id              = "$AZURE_SUBSCRIPTION_ID"
terraform_sp_app_id          = "$AZURE_SP_ID"
dns_zone_id                  = "$AZURE_DNS_ZONE_ID"
domain_name                  = "$DOMAIN_NAME"
enable_webmodeler            = ${WEBMODELER_ENABLED:-false}
identity_initial_user_email  = "${MAIL_OVERWRITE:-admin@camunda.ie}"
EOF

cat terraform.tfvars
