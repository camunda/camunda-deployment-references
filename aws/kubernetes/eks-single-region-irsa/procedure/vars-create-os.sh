#!/bin/bash

# OpenSearch Credentials (replace with your own values from the #opensearch-module-setup step)
# Preserve export's masked substitution status when errexit is enabled.
OPENSEARCH_MASTER_USERNAME="$(terraform console <<<local.opensearch_master_username | tail -n 1 | jq -r)" || true
export OPENSEARCH_MASTER_USERNAME
# terraform output -raw handles sensitive values correctly (terraform console prints "(sensitive value)" for them)
OPENSEARCH_MASTER_PASSWORD="$(terraform output -raw opensearch_master_password)" || true
export OPENSEARCH_MASTER_PASSWORD
