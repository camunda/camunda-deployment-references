#!/bin/bash
set -euo pipefail

# Retrieve all outputs as JSON
outputs_json=$(terraform output -json)

# PostgreSQL connection details
DB_HOST=$(echo "$outputs_json" | jq -r .postgres_fqdn.value)
export DB_HOST
export DB_PORT=5432

# PostgreSQL version (e.g. 17)
POSTGRES_VERSION=$(echo "$outputs_json" | jq -r .postgres_version.value)
export POSTGRES_VERSION
export POSTGRES_MAJOR_VERSION="$POSTGRES_VERSION"

# PostgreSQL Admin Credentials
POSTGRES_ADMIN_USERNAME=$(echo "$outputs_json" | jq -r .postgres_admin_username.value)
export POSTGRES_ADMIN_USERNAME
POSTGRES_ADMIN_PASSWORD=$(echo "$outputs_json" | jq -r .postgres_admin_password.value)
export POSTGRES_ADMIN_PASSWORD

# Identity DB
DB_IDENTITY_NAME=$(echo "$outputs_json" | jq -r .camunda_database_identity.value)
export DB_IDENTITY_NAME
DB_IDENTITY_USERNAME=$(echo "$outputs_json" | jq -r .camunda_identity_db_username.value)
export DB_IDENTITY_USERNAME
DB_IDENTITY_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_identity_db_password.value)
export DB_IDENTITY_PASSWORD

# Web Modeler DB
DB_WEBMODELER_NAME=$(echo "$outputs_json" | jq -r .camunda_database_webmodeler.value)
export DB_WEBMODELER_NAME
DB_WEBMODELER_USERNAME=$(echo "$outputs_json" | jq -r .camunda_webmodeler_db_username.value)
export DB_WEBMODELER_USERNAME
DB_WEBMODELER_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_webmodeler_db_password.value)
export DB_WEBMODELER_PASSWORD

# Orchestration DB (RDBMS secondary storage)
DB_ORCHESTRATION_NAME=$(echo "$outputs_json" | jq -r .camunda_database_orchestration.value)
export DB_ORCHESTRATION_NAME
DB_ORCHESTRATION_USERNAME=$(echo "$outputs_json" | jq -r .camunda_orchestration_db_username.value)
export DB_ORCHESTRATION_USERNAME
DB_ORCHESTRATION_PASSWORD=$(echo "$outputs_json" | jq -r .camunda_orchestration_db_password.value)
export DB_ORCHESTRATION_PASSWORD
