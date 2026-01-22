#!/bin/bash

# Export Keycloak Helm values (CI/Test only - for embedded Keycloak)
# This script exports ONLY Keycloak-specific variables
# Run after export-helm-values.sh when using embedded Keycloak

export DB_KEYCLOAK_NAME="$(terraform console <<<local.camunda_database_keycloak | tail -n 1 | jq -r)"
export DB_KEYCLOAK_USERNAME="$(terraform console <<<local.camunda_keycloak_db_username | tail -n 1 | jq -r)"
export DB_KEYCLOAK_PASSWORD="$(terraform console <<<local.camunda_keycloak_db_password | tail -n 1 | jq -r)"
