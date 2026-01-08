#!/bin/bash
# Check if all required environment variables are set (without Keycloak)

set -euo pipefail

required_vars=("DB_HOST" "DB_PORT" "DB_IDENTITY_NAME" "DB_IDENTITY_USERNAME" "DB_IDENTITY_PASSWORD" "DB_WEBMODELER_NAME" "DB_WEBMODELER_USERNAME" "DB_WEBMODELER_PASSWORD")

missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "Error: The following required environment variables are not set:"
    printf '  - %s\n' "${missing_vars[@]}"
    exit 1
fi

echo "All required environment variables are set!"
