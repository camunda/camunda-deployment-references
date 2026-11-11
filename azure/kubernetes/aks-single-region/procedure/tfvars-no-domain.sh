#!/bin/bash

export AZURE_SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)

cat <<EOF > terraform.tfvars
subscription_id     = "$AZURE_SUBSCRIPTION_ID"
terraform_sp_app_id = "$AZURE_SP_ID"
EOF

cat terraform.tfvars
