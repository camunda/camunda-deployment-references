# EKS Cluster
export CERT_MANAGER_IRSA_ARN="$(terraform output -raw cert_manager_arn)"
export EXTERNAL_DNS_IRSA_ARN="$(terraform output -raw external_dns_arn)"

# PostgreSQL
export DB_KEYCLOAK_NAME="$(terraform console <<<local.camunda_database_keycloak | jq -r)"
export DB_KEYCLOAK_USERNAME="$(terraform console <<<local.camunda_keycloak_db_username | jq -r)"
export DB_KEYCLOAK_PASSWORD="$(terraform console <<<local.camunda_keycloak_db_password | jq -r)"

export DB_IDENTITY_NAME="$(terraform console <<<local.camunda_database_identity | jq -r)"
export DB_IDENTITY_USERNAME="$(terraform console <<<local.camunda_identity_db_username | jq -r)"
export DB_IDENTITY_PASSWORD="$(terraform console <<<local.camunda_identity_db_password | jq -r)"

export DB_WEBMODELER_NAME="$(terraform console <<<local.camunda_database_webmodeler | jq -r)"
export DB_WEBMODELER_USERNAME="$(terraform console <<<local.camunda_webmodeler_db_username | jq -r)"
export DB_WEBMODELER_PASSWORD="$(terraform console <<<local.camunda_webmodeler_db_password | jq -r)"

export DB_HOST="$(terraform output -raw postgres_endpoint)"

# OpenSearch
export OPENSEARCH_HOST="$(terraform output -raw opensearch_endpoint)"
