#!/bin/bash

export AZURE_SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)

export AZURE_SP_ID=$(az ad sp list --display-name "$AZURE_SP_NAME" --query "[0].appId" -o tsv)

export AZURE_DNS_ZONE_ID=$(az network dns zone show \
  --name "$TLD" \
  --resource-group "$AZURE_DNS_RESOURCE_GROUP" \
  --query "id" -o tsv)

cat <<EOF > terraform.tfvars
subscription_id     = "$AZURE_SUBSCRIPTION_ID"
terraform_sp_app_id = "$AZURE_SP_ID"
dns_zone_id         = "$AZURE_DNS_ZONE_ID"
EOF
