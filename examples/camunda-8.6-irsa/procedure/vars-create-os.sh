# OpenSearch Credentials (replace with your own values from the #opensearch-module-setup step)
export OPENSEARCH_MASTER_USERNAME="$(terraform console <<<local.opensearch_master_username | jq -r)"
export OPENSEARCH_MASTER_PASSWORD="$(terraform console <<<local.opensearch_master_password | jq -r)"
