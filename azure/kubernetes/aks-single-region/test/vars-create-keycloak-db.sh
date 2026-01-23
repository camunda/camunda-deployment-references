#!/bin/bash

# Export Keycloak database variables from Terraform outputs (CI/Test only)
# Run after vars-create-db.sh when using embedded Keycloak

# Retrieve all outputs as JSON
outputs_json=$(terraform output -json)

# Keycloak DB
export DB_KEYCLOAK_NAME=$(echo "$outputs_json" | jq -r .camunda_database_keycloak.value)
export DB_KEYCLOAK_USERNAME=$(echo "$outputs_json" | jq -r .camunda_keycloak_db_username.value)
export DB_KEYCLOAK_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_keycloak_db_password.value)
