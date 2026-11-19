#!/bin/bash

# Retrieve all outputs as JSON
outputs_json=$(terraform output -json)

# PostgreSQL connection details
# Preserve export's masked substitution status when errexit is enabled.
DB_HOST=$(echo "$outputs_json" | jq -r .postgres_fqdn.value) || true
export DB_HOST
export DB_PORT=5432

# PostgreSQL Admin Credentials
POSTGRES_ADMIN_USERNAME=$(echo "$outputs_json" | jq -r .postgres_admin_username.value) || true
export POSTGRES_ADMIN_USERNAME
POSTGRES_ADMIN_PASSWORD=$(echo "$outputs_json" | jq -r .postgres_admin_password.value) || true
export POSTGRES_ADMIN_PASSWORD

# Keycloak DB
DB_KEYCLOAK_NAME=$(echo "$outputs_json" | jq -r .camunda_database_keycloak.value) || true
export DB_KEYCLOAK_NAME
DB_KEYCLOAK_USERNAME=$(echo "$outputs_json" | jq -r .camunda_keycloak_db_username.value) || true
export DB_KEYCLOAK_USERNAME
DB_KEYCLOAK_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_keycloak_db_password.value) || true
export DB_KEYCLOAK_PASSWORD

# Identity DB
DB_IDENTITY_NAME=$(echo "$outputs_json" | jq -r .camunda_database_identity.value) || true
export DB_IDENTITY_NAME
DB_IDENTITY_USERNAME=$(echo "$outputs_json" | jq -r .camunda_identity_db_username.value) || true
export DB_IDENTITY_USERNAME
DB_IDENTITY_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_identity_db_password.value) || true
export DB_IDENTITY_PASSWORD

# Web Modeler DB
DB_WEBMODELER_NAME=$(echo "$outputs_json" | jq -r .camunda_database_webmodeler.value) || true
export DB_WEBMODELER_NAME
DB_WEBMODELER_USERNAME=$(echo "$outputs_json" | jq -r .camunda_webmodeler_db_username.value) || true
export DB_WEBMODELER_USERNAME
DB_WEBMODELER_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_webmodeler_db_password.value) || true
export DB_WEBMODELER_PASSWORD
