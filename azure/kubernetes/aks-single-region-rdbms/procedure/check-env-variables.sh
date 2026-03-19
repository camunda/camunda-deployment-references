#!/bin/bash

# This script is compatible with bash only

# List of required environment variables for the RDBMS secondary storage variant
required_vars=("DB_HOST" "DB_PORT" "DB_IDENTITY_NAME" "DB_IDENTITY_USERNAME" "DB_IDENTITY_PASSWORD" "RDBMS_SECONDARY_DATABASE" "RDBMS_SECONDARY_USERNAME" "RDBMS_SECONDARY_PASSWORD")

# Loop through each variable and check if it is set and not empty
for var in "${required_vars[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set or is empty"
  else
    echo "$var is set to '${!var}'"
  fi
done
