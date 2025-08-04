#!/bin/bash

# OpenSearch Credentials (replace with your own values from the #opensearch-module-setup step)
export OPENSEARCH_MASTER_USERNAME="$(terraform console <<<local.opensearch_master_username | tail -n 1 | jq -r)"
export OPENSEARCH_MASTER_PASSWORD="$(terraform console <<<local.opensearch_master_password | tail -n 1 | jq -r)"
