#!/bin/bash

az storage account blob-service-properties show \
  --account-name "$AZURE_STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query "isVersioningEnabled"
