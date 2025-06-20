#!/bin/bash

az group create \
  --name "$RESOURCE_GROUP_NAME" \
  --location "$AZURE_LOCATION"

az storage account create \
  --name "$AZURE_STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --location "$AZURE_LOCATION" \
  --sku Standard_LRS \
  --encryption-services blob

az storage container create \
  --name "$AZURE_STORAGE_CONTAINER_NAME" \
  --account-name "$AZURE_STORAGE_ACCOUNT_NAME" \
  --auth-mode login
