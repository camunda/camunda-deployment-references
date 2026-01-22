#!/bin/bash
# Export Cognito variables from Terraform outputs for CI tests
# This script is used by the CI workflow to get Cognito configuration

set -euo pipefail

# Check if Cognito is enabled
COGNITO_ENABLED=$(terraform output -raw cognito_enabled 2>/dev/null || echo "false")

if [ "$COGNITO_ENABLED" != "true" ]; then
    echo "COGNITO_ENABLED=false"
    exit 0
fi

echo "COGNITO_ENABLED=true"

# OIDC Endpoints
export COGNITO_ISSUER_URL
COGNITO_ISSUER_URL=$(terraform output -raw cognito_issuer_url)
echo "COGNITO_ISSUER_URL=$COGNITO_ISSUER_URL"

export COGNITO_JWKS_URL
COGNITO_JWKS_URL=$(terraform output -raw cognito_jwks_url)
echo "COGNITO_JWKS_URL=$COGNITO_JWKS_URL"

export COGNITO_TOKEN_URL
COGNITO_TOKEN_URL=$(terraform output -raw cognito_token_url)
echo "COGNITO_TOKEN_URL=$COGNITO_TOKEN_URL"

export COGNITO_AUTHORIZATION_URL
COGNITO_AUTHORIZATION_URL=$(terraform output -raw cognito_authorization_url)
echo "COGNITO_AUTHORIZATION_URL=$COGNITO_AUTHORIZATION_URL"

export COGNITO_SECRET_NAME
COGNITO_SECRET_NAME=$(terraform output -raw cognito_secret_name)
echo "COGNITO_SECRET_NAME=$COGNITO_SECRET_NAME"

export COGNITO_SECRET_ARN
COGNITO_SECRET_ARN=$(terraform output -raw cognito_secret_arn)
echo "COGNITO_SECRET_ARN=$COGNITO_SECRET_ARN"

# Client IDs (non-sensitive)
export IDENTITY_CLIENT_ID
IDENTITY_CLIENT_ID=$(terraform output -raw identity_client_id)
echo "IDENTITY_CLIENT_ID=$IDENTITY_CLIENT_ID"

export OPTIMIZE_CLIENT_ID
OPTIMIZE_CLIENT_ID=$(terraform output -raw optimize_client_id)
echo "OPTIMIZE_CLIENT_ID=$OPTIMIZE_CLIENT_ID"

export ORCHESTRATION_CLIENT_ID
ORCHESTRATION_CLIENT_ID=$(terraform output -raw orchestration_client_id)
echo "ORCHESTRATION_CLIENT_ID=$ORCHESTRATION_CLIENT_ID"

export CONNECTORS_CLIENT_ID
CONNECTORS_CLIENT_ID=$(terraform output -raw connectors_client_id)
echo "CONNECTORS_CLIENT_ID=$CONNECTORS_CLIENT_ID"

export CONSOLE_CLIENT_ID
CONSOLE_CLIENT_ID=$(terraform output -raw console_client_id 2>/dev/null || echo "")
echo "CONSOLE_CLIENT_ID=$CONSOLE_CLIENT_ID"

export WEBMODELER_UI_CLIENT_ID
WEBMODELER_UI_CLIENT_ID=$(terraform output -raw webmodeler_ui_client_id 2>/dev/null || echo "")
echo "WEBMODELER_UI_CLIENT_ID=$WEBMODELER_UI_CLIENT_ID"

export WEBMODELER_API_CLIENT_ID
WEBMODELER_API_CLIENT_ID=$(terraform output -raw webmodeler_api_client_id 2>/dev/null || echo "")
echo "WEBMODELER_API_CLIENT_ID=$WEBMODELER_API_CLIENT_ID"

# Initial user email
export IDENTITY_INITIAL_USER_EMAIL
IDENTITY_INITIAL_USER_EMAIL=$(terraform output -raw cognito_initial_user_email 2>/dev/null || echo "admin@camunda.local")
echo "IDENTITY_INITIAL_USER_EMAIL=$IDENTITY_INITIAL_USER_EMAIL"
