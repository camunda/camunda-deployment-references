#!/bin/bash
# Export Cognito environment variables from AWS Secrets Manager
# This script is designed to be sourced from the terraform/cluster directory
# or to auto-detect the correct directory when run standalone

set -euo pipefail

# If we're not in the terraform directory, try to find it
if ! terraform output -raw cognito_enabled &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TERRAFORM_DIR="${SCRIPT_DIR}/../terraform/cluster"
    if [ -d "$TERRAFORM_DIR" ]; then
        cd "$TERRAFORM_DIR"
    fi
fi

# Check if Cognito is enabled
COGNITO_ENABLED=$(terraform output -raw cognito_enabled 2>/dev/null || echo "false")

if [ "$COGNITO_ENABLED" != "true" ]; then
    echo "Cognito is not enabled. Skipping Cognito variable export."
    exit 0
fi

echo "Exporting Cognito configuration from Terraform and AWS Secrets Manager..."

# Get AWS Secrets Manager secret name
export COGNITO_SECRET_NAME
COGNITO_SECRET_NAME=$(terraform output -raw cognito_secret_name)

export COGNITO_SECRET_ARN
COGNITO_SECRET_ARN=$(terraform output -raw cognito_secret_arn)

echo "Retrieving Cognito credentials from AWS Secrets Manager: $COGNITO_SECRET_NAME"

# Get secret from AWS Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$COGNITO_SECRET_NAME" \
    --query 'SecretString' \
    --output text)

# Export Cognito endpoints
export COGNITO_USER_POOL_ID
COGNITO_USER_POOL_ID=$(echo "$SECRET_JSON" | jq -r '.user_pool_id')

export COGNITO_ISSUER_URL
COGNITO_ISSUER_URL=$(echo "$SECRET_JSON" | jq -r '.issuer_url')

export COGNITO_JWKS_URL
COGNITO_JWKS_URL=$(echo "$SECRET_JSON" | jq -r '.jwks_url')

export COGNITO_TOKEN_URL
COGNITO_TOKEN_URL=$(echo "$SECRET_JSON" | jq -r '.token_url')

export COGNITO_AUTHORIZATION_URL
COGNITO_AUTHORIZATION_URL=$(echo "$SECRET_JSON" | jq -r '.authorization_url')

# Export domain and user
export COGNITO_DOMAIN_NAME
COGNITO_DOMAIN_NAME=$(echo "$SECRET_JSON" | jq -r '.domain_name')

export IDENTITY_INITIAL_USER_EMAIL
IDENTITY_INITIAL_USER_EMAIL=$(echo "$SECRET_JSON" | jq -r '.identity_initial_user_email')

# Identity
export IDENTITY_CLIENT_ID
IDENTITY_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.identity_client_id')
export IDENTITY_CLIENT_SECRET
IDENTITY_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.identity_client_secret')

# Optimize
export OPTIMIZE_CLIENT_ID
OPTIMIZE_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.optimize_client_id')
export OPTIMIZE_CLIENT_SECRET
OPTIMIZE_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.optimize_client_secret')

# Orchestration
export ORCHESTRATION_CLIENT_ID
ORCHESTRATION_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.orchestration_client_id')
export ORCHESTRATION_CLIENT_SECRET
ORCHESTRATION_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.orchestration_client_secret')

# Console
export CONSOLE_CLIENT_ID
CONSOLE_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.console_client_id')

# Connectors
export CONNECTORS_CLIENT_ID
CONNECTORS_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.connectors_client_id')
export CONNECTORS_CLIENT_SECRET
CONNECTORS_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.connectors_client_secret')

# WebModeler (optional)
export WEBMODELER_UI_CLIENT_ID
WEBMODELER_UI_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.webmodeler_ui_client_id // empty')
export WEBMODELER_API_CLIENT_ID
WEBMODELER_API_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.webmodeler_api_client_id // empty')
export WEBMODELER_API_CLIENT_SECRET
WEBMODELER_API_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.webmodeler_api_client_secret // empty')

echo "Cognito configuration exported successfully"
echo "Cognito Issuer URL: $COGNITO_ISSUER_URL"
echo "Domain Name: $COGNITO_DOMAIN_NAME"
echo "Identity Client ID: $IDENTITY_CLIENT_ID"
echo "Optimize Client ID: $OPTIMIZE_CLIENT_ID"
echo "Orchestration Client ID: $ORCHESTRATION_CLIENT_ID"
echo "Console Client ID: $CONSOLE_CLIENT_ID"
echo "Connectors Client ID: $CONNECTORS_CLIENT_ID"
if [ -n "$WEBMODELER_UI_CLIENT_ID" ]; then
    echo "WebModeler UI Client ID: $WEBMODELER_UI_CLIENT_ID"
    echo "WebModeler API Client ID: $WEBMODELER_API_CLIENT_ID"
fi
