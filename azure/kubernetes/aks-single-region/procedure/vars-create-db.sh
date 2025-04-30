#!/bin/bash

# PostgreSQL connection details
export POSTGRES_FQDN=$(terraform output -raw postgres_fqdn)
export POSTGRES_PORT=5432

# PostgreSQL Admin Credentials
export POSTGRES_ADMIN_USERNAME=$(terraform output -raw postgres_admin_username)
export POSTGRES_ADMIN_PASSWORD=$(terraform output -raw postgres_admin_password)

export DB_KEYCLOAK_NAME="$(terraform console <<<local.camunda_database_keycloak | jq -r)"
export DB_KEYCLOAK_USERNAME="$(terraform console <<<local.camunda_keycloak_db_username | jq -r)"
export DB_KEYCLOAK_PASSWORD="$(terraform console <<<local.camunda_keycloak_db_password | jq -r)"

export DB_IDENTITY_NAME="$(terraform console <<<local.camunda_database_identity | jq -r)"
export DB_IDENTITY_USERNAME="$(terraform console <<<local.camunda_identity_db_username | jq -r)"
export DB_IDENTITY_PASSWORD="$(terraform console <<<local.camunda_identity_db_password | jq -r)"

export DB_WEBMODELER_NAME="$(terraform console <<<local.camunda_database_webmodeler | jq -r)"
export DB_WEBMODELER_USERNAME="$(terraform console <<<local.camunda_webmodeler_db_username | jq -r)"
export DB_WEBMODELER_PASSWORD="$(terraform console <<<local.camunda_webmodeler_db_password | jq -r)"
