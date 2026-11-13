#!/bin/bash

# EKS Cluster
CERT_MANAGER_IRSA_ARN="$(terraform output -raw cert_manager_arn)"
export CERT_MANAGER_IRSA_ARN
EXTERNAL_DNS_IRSA_ARN="$(terraform output -raw external_dns_arn)"
export EXTERNAL_DNS_IRSA_ARN

# PostgreSQL
DB_IDENTITY_NAME="$(terraform console <<<local.camunda_database_identity | tail -n 1 | jq -r)"
export DB_IDENTITY_NAME
DB_IDENTITY_USERNAME="$(terraform console <<<local.camunda_identity_db_username | tail -n 1 | jq -r)"
export DB_IDENTITY_USERNAME
DB_IDENTITY_PASSWORD="$(terraform output -raw camunda_identity_db_password)"
export DB_IDENTITY_PASSWORD

DB_WEBMODELER_NAME="$(terraform console <<<local.camunda_database_webmodeler | tail -n 1 | jq -r)"
export DB_WEBMODELER_NAME
DB_WEBMODELER_USERNAME="$(terraform console <<<local.camunda_webmodeler_db_username | tail -n 1 | jq -r)"
export DB_WEBMODELER_USERNAME
DB_WEBMODELER_PASSWORD="$(terraform output -raw camunda_webmodeler_db_password)"
export DB_WEBMODELER_PASSWORD

DB_HOST="$(terraform output -raw postgres_endpoint)"
export DB_HOST
export DB_PORT=5432

# OpenSearch
OPENSEARCH_HOST="$(terraform output -raw opensearch_endpoint)"
export OPENSEARCH_HOST
