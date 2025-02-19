# This script is compatible with bash only

# List of required environment variables
required_vars=("DB_HOST" "DB_KEYCLOAK_NAME" "DB_KEYCLOAK_USERNAME" "DB_KEYCLOAK_PASSWORD" "DB_IDENTITY_NAME" "DB_IDENTITY_USERNAME" "DB_IDENTITY_PASSWORD" "DB_WEBMODELER_NAME" "DB_WEBMODELER_USERNAME" "DB_WEBMODELER_PASSWORD" "OPENSEARCH_HOST")

# Loop through each variable and check if it is set and not empty
for var in "${required_vars[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set or is empty"
  else
    echo "$var is set to '${!var}'"
  fi
done
