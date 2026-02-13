#!/bin/bash

# Retrieve all outputs as JSON
outputs_json=$(terraform output -json)

# PostgreSQL connection details
export DB_HOST=$(echo "$outputs_json" | jq -r .postgres_fqdn.value)
export DB_PORT=5432

# PostgreSQL Admin Credentials
export POSTGRES_ADMIN_USERNAME=$(echo "$outputs_json" | jq -r .postgres_admin_username.value)
export POSTGRES_ADMIN_PASSWORD=$(echo "$outputs_json" | jq -r .postgres_admin_password.value)

# Identity DB
export DB_IDENTITY_NAME=$(echo "$outputs_json" | jq -r .camunda_database_identity.value)
export DB_IDENTITY_USERNAME=$(echo "$outputs_json" | jq -r .camunda_identity_db_username.value)
export DB_IDENTITY_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_identity_db_password.value)

# Web Modeler DB
export DB_WEBMODELER_NAME=$(echo "$outputs_json" | jq -r .camunda_database_webmodeler.value)
export DB_WEBMODELER_USERNAME=$(echo "$outputs_json" | jq -r .camunda_webmodeler_db_username.value)
export DB_WEBMODELER_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_webmodeler_db_password.value)
