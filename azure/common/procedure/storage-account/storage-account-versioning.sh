#!/bin/bash

az storage account blob-service-properties update \
  --account-name "$AZURE_STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --enable-versioning true
