# This script is compatible with bash only

# List of required environment variables
required_vars=("DB_HOST" "DB_ROLE_IDENTITY_ARN" "DB_ROLE_KEYCLOAK_ARN" "DB_ROLE_WEBMODELER_ARN" "CAMUNDA_WEBMODELER_SERVICE_ACCOUNT_NAME" "DB_WEBMODELER_NAME" "DB_WEBMODELER_USERNAME" "CAMUNDA_IDENTITY_SERVICE_ACCOUNT_NAME" "DB_IDENTITY_NAME" "DB_IDENTITY_USERNAME" "DB_KEYCLOAK_NAME" "DB_KEYCLOAK_USERNAME" "CAMUNDA_KEYCLOAK_SERVICE_ACCOUNT_NAME" "OPENSEARCH_HOST" "OPENSEARCH_ROLE_ARN"  "CAMUNDA_ZEEBE_SERVICE_ACCOUNT_NAME" "CAMUNDA_OPERATE_SERVICE_ACCOUNT_NAME" "CAMUNDA_TASKLIST_SERVICE_ACCOUNT_NAME" "CAMUNDA_OPTIMIZE_SERVICE_ACCOUNT_NAME")

# Loop through each variable and check if it is set and not empty
for var in "${required_vars[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set or is empty"
  else
    echo "$var is set to '${!var}'"
  fi
done
