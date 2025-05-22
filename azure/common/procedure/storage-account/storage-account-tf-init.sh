#!/bin/bash

export AZURE_TF_KEY="camunda-terraform/terraform.tfstate"

export ARM_ACCESS_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --account-name "$AZURE_STORAGE_ACCOUNT_NAME" \
  --query '[0].value' \
  --output tsv)

echo "Storing Terraform state in https://$AZURE_STORAGE_ACCOUNT_NAME.blob.core.windows.net/$AZURE_STORAGE_CONTAINER_NAME/$AZURE_TF_KEY"

terraform init \
  -backend-config="storage_account_name=$AZURE_STORAGE_ACCOUNT_NAME" \
  -backend-config="container_name=$AZURE_STORAGE_CONTAINER_NAME" \
  -backend-config="key=$AZURE_TF_KEY" \
  -backend-config="access_key=$ARM_ACCESS_KEY"
