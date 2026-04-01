#!/bin/bash

# This script is compatible with bash only
# Note: Keycloak variables are only required when using embedded Keycloak (not external OIDC)

# List of required environment variables (base configuration + RDBMS orchestration)
required_vars=("DB_HOST" "DB_PORT" "DB_IDENTITY_NAME" "DB_IDENTITY_USERNAME" "DB_IDENTITY_PASSWORD" "DB_WEBMODELER_NAME" "DB_WEBMODELER_USERNAME" "DB_WEBMODELER_PASSWORD" "DB_ORCHESTRATION_NAME" "DB_ORCHESTRATION_USERNAME" "DB_ORCHESTRATION_PASSWORD")

# Loop through each variable and check if it is set and not empty
missing_var=0
for var in "${required_vars[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set or is empty"
    missing_var=1
  else
    echo "$var is set"
  fi
done

exit $missing_var
