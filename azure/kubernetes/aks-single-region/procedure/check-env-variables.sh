#!/bin/bash

# This script is compatible with bash only
# Note: Keycloak variables are only required when using embedded Keycloak (not external OIDC)

# List of required environment variables (base configuration)
required_vars=("DB_HOST" "DB_PORT" "DB_IDENTITY_NAME" "DB_IDENTITY_USERNAME" "DB_IDENTITY_PASSWORD" "DB_WEBMODELER_NAME" "DB_WEBMODELER_USERNAME" "DB_WEBMODELER_PASSWORD")

# Loop through each variable and check if it is set and not empty
for var in "${required_vars[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set or is empty"
  else
    echo "$var is set to '${!var}'"
  fi
done
