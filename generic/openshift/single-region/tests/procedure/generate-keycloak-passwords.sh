#!/bin/bash

# Generate passwords for Keycloak embedded PostgreSQL (CI/Test only - for embedded Keycloak)
# Source this file after generate-passwords.sh when using embedded Keycloak

export KEYCLOAK_PSQL_ADMIN_PASSWORD="$(openssl rand -hex 16)"
export KEYCLOAK_PSQL_USER_PASSWORD="$(openssl rand -hex 16)"
