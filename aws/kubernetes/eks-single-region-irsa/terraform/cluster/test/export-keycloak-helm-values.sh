#!/bin/bash

# Export Keycloak Helm values for IRSA (CI/Test only - for embedded Keycloak)
# This script exports ONLY Keycloak-specific variables
# Run after export-helm-values.sh when using embedded Keycloak

export DB_KEYCLOAK_NAME="$(terraform console <<<local.camunda_database_keycloak | tail -n 1 | jq -r)"
export DB_KEYCLOAK_USERNAME="$(terraform console <<<local.camunda_keycloak_db_username | tail -n 1 | jq -r)"
export CAMUNDA_KEYCLOAK_SERVICE_ACCOUNT_NAME="$(terraform console <<<local.camunda_keycloak_service_account | tail -n 1 | jq -r)"

export DB_ROLE_KEYCLOAK_NAME="$(terraform console <<<local.camunda_keycloak_role_name | tail -n 1 | jq -r)"
export DB_ROLE_KEYCLOAK_ARN="$(terraform output -raw keycloak_aurora_iam_role_arn)"
