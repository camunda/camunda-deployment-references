#!/bin/bash

# PostgreSQL connection details
export POSTGRES_FQDN=$(terraform output -raw postgres_fqdn)
export POSTGRES_PORT=5432

# PostgreSQL Admin Credentials
export POSTGRES_ADMIN_USERNAME=$(terraform output -raw postgres_admin_username)
export POSTGRES_ADMIN_PASSWORD=$(terraform output -raw postgres_admin_password)

# Database names
export DB_KEYCLOAK_NAME="camunda_keycloak"
export DB_IDENTITY_NAME="camunda_identity"
export DB_WEBMODELER_NAME="camunda_webmodeler"

# Database users
export DB_KEYCLOAK_USERNAME="keycloak_user"
export DB_IDENTITY_USERNAME="identity_user"
export DB_WEBMODELER_USERNAME="webmodeler_user"

# Database passwords
export DB_KEYCLOAK_PASSWORD="Keycloak1234!"   # For testing only - use secure passwords in production
export DB_IDENTITY_PASSWORD="Identity1234!"   # For testing only - use secure passwords in production
export DB_WEBMODELER_PASSWORD="Webmodeler1234!"  # For testing only - use secure passwords in production
