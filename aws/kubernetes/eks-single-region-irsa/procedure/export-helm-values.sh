#!/bin/bash

# EKS Cluster
export CERT_MANAGER_IRSA_ARN="$(terraform output -raw cert_manager_arn)"
export EXTERNAL_DNS_IRSA_ARN="$(terraform output -raw external_dns_arn)"

# PostgreSQL
export DB_IDENTITY_NAME="$(terraform console <<<local.camunda_database_identity | tail -n 1 | jq -r)"
export DB_IDENTITY_USERNAME="$(terraform console <<<local.camunda_identity_db_username | tail -n 1 | jq -r)"
export CAMUNDA_IDENTITY_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_identity_service_account | tail -n 1 | jq -r)"

export DB_WEBMODELER_NAME="$(terraform console <<<local.camunda_database_webmodeler | tail -n 1 | jq -r)"
export DB_WEBMODELER_USERNAME="$(terraform console <<<local.camunda_webmodeler_db_username | tail -n 1 | jq -r)"
export CAMUNDA_WEBMODELER_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_webmodeler_service_account | tail -n 1 | jq -r)"

export DB_HOST="$(terraform output -raw postgres_endpoint)"
export DB_ROLE_IDENTITY_NAME="$(terraform console <<<local.camunda_identity_role_name | tail -n 1 | jq -r)"
export DB_ROLE_IDENTITY_ARN=$(terraform output -json aurora_iam_role_arns | jq -r ".[\"$DB_ROLE_IDENTITY_NAME\"]")
export DB_ROLE_WEBMODELER_NAME="$(terraform console <<<local.camunda_webmodeler_role_name | tail -n 1 | jq -r)"
export DB_ROLE_WEBMODELER_ARN=$(terraform output -json aurora_iam_role_arns | jq -r ".[\"$DB_ROLE_WEBMODELER_NAME\"]")

# OpenSearch
export OPENSEARCH_HOST="$(terraform output -raw opensearch_endpoint)"
export OPENSEARCH_ROLE_NAME="$(terraform console <<<local.opensearch_iam_role_name | tail -n 1 | jq -r)"
export OPENSEARCH_ROLE_ARN=$(terraform output -json opensearch_iam_role_arns | jq -r ".[\"$OPENSEARCH_ROLE_NAME\"]")
export CAMUNDA_ZEEBE_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_zeebe_service_account | tail -n 1 | jq -r)"
export CAMUNDA_OPTIMIZE_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_optimize_service_account | tail -n 1 | jq -r)"
