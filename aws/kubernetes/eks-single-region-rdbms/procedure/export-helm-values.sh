#!/bin/bash

# EKS Cluster
export CERT_MANAGER_IRSA_ARN="$(terraform output -raw cert_manager_arn)"
export EXTERNAL_DNS_IRSA_ARN="$(terraform output -raw external_dns_arn)"

# PostgreSQL
export DB_IDENTITY_NAME="$(terraform console <<<local.camunda_database_identity | tail -n 1 | jq -r)"
export DB_IDENTITY_USERNAME="$(terraform console <<<local.camunda_identity_db_username | tail -n 1 | jq -r)"
export DB_IDENTITY_PASSWORD="$(terraform console <<<local.camunda_identity_db_password | tail -n 1 | jq -r)"

export DB_WEBMODELER_NAME="$(terraform console <<<local.camunda_database_webmodeler | tail -n 1 | jq -r)"
export DB_WEBMODELER_USERNAME="$(terraform console <<<local.camunda_webmodeler_db_username | tail -n 1 | jq -r)"
export DB_WEBMODELER_PASSWORD="$(terraform console <<<local.camunda_webmodeler_db_password | tail -n 1 | jq -r)"

# RDBMS Secondary Storage (Operate + Tasklist)
export DB_OPERATE_NAME="$(terraform console <<<local.camunda_database_operate | tail -n 1 | jq -r)"
export DB_OPERATE_USERNAME="$(terraform console <<<local.camunda_operate_db_username | tail -n 1 | jq -r)"
export DB_OPERATE_PASSWORD="$(terraform console <<<local.camunda_operate_db_password | tail -n 1 | jq -r)"

export DB_HOST="$(terraform output -raw postgres_endpoint)"
