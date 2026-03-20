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

# RDBMS secondary storage DB (replaces Elasticsearch/OpenSearch)
export RDBMS_SECONDARY_DATABASE=$(echo "$outputs_json" | jq -r .camunda_database_secondary.value)
export RDBMS_SECONDARY_USERNAME=$(echo "$outputs_json" | jq -r .camunda_secondary_db_username.value)
export RDBMS_SECONDARY_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_secondary_db_password.value)
