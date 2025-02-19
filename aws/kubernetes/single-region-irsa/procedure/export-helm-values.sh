# EKS Cluster
export CERT_MANAGER_IRSA_ARN="$(terraform output -raw cert_manager_arn)"
export EXTERNAL_DNS_IRSA_ARN="$(terraform output -raw external_dns_arn)"

# PostgreSQL
export DB_KEYCLOAK_NAME="$(terraform console <<<local.camunda_database_keycloak | jq -r)"
export DB_KEYCLOAK_USERNAME="$(terraform console <<<local.camunda_keycloak_db_username | jq -r)"
export CAMUNDA_KEYCLOAK_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_keycloak_service_account | jq -r)"

export DB_IDENTITY_NAME="$(terraform console <<<local.camunda_database_identity | jq -r)"
export DB_IDENTITY_USERNAME="$(terraform console <<<local.camunda_identity_db_username | jq -r)"
export CAMUNDA_IDENTITY_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_identity_service_account | jq -r)"

export DB_WEBMODELER_NAME="$(terraform console <<<local.camunda_database_webmodeler | jq -r)"
export DB_WEBMODELER_USERNAME="$(terraform console <<<local.camunda_webmodeler_db_username | jq -r)"
export CAMUNDA_WEBMODELER_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_webmodeler_service_account | jq -r)"

export DB_HOST="$(terraform output -raw postgres_endpoint)"
export DB_ROLE_KEYCLOAK_NAME="$(terraform console <<<local.camunda_keycloak_role_name | jq -r)"
export DB_ROLE_KEYCLOAK_ARN=$(terraform output -json aurora_iam_role_arns | jq -r ".[\"$DB_ROLE_KEYCLOAK_NAME\"]")
export DB_ROLE_IDENTITY_NAME="$(terraform console <<<local.camunda_identity_role_name | jq -r)"
export DB_ROLE_IDENTITY_ARN=$(terraform output -json aurora_iam_role_arns | jq -r ".[\"$DB_ROLE_IDENTITY_NAME\"]")
export DB_ROLE_WEBMODELER_NAME="$(terraform console <<<local.camunda_webmodeler_role_name | jq -r)"
export DB_ROLE_WEBMODELER_ARN=$(terraform output -json aurora_iam_role_arns | jq -r ".[\"$DB_ROLE_WEBMODELER_NAME\"]")

# OpenSearch
export OPENSEARCH_HOST="$(terraform output -raw opensearch_endpoint)"
export OPENSEARCH_ROLE_NAME="$(terraform console <<<local.opensearch_iam_role_name | jq -r)"
export OPENSEARCH_ROLE_ARN=$(terraform output -json opensearch_iam_role_arns | jq -r ".[\"$OPENSEARCH_ROLE_NAME\"]")
export CAMUNDA_ZEEBE_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_zeebe_service_account | jq -r)"
export CAMUNDA_OPERATE_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_operate_service_account | jq -r)"
export CAMUNDA_TASKLIST_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_tasklist_service_account | jq -r)"
export CAMUNDA_OPTIMIZE_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_optimize_service_account | jq -r)"
