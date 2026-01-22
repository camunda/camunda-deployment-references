#!/bin/bash
# Export Cognito OIDC environment variables for Helm chart installation
# This script is used in CI/CD to pass Cognito configuration to helm values

# These variables should be set by the CI system or manually before running this script

export COGNITO_USER_POOL_ID="${COGNITO_USER_POOL_ID:-}"
export COGNITO_ISSUER_URL="${COGNITO_ISSUER_URL:-}"
export COGNITO_AUTHORIZATION_URL="${COGNITO_AUTHORIZATION_URL:-}"
export COGNITO_TOKEN_URL="${COGNITO_TOKEN_URL:-}"
export COGNITO_JWKS_URL="${COGNITO_JWKS_URL:-}"
export COGNITO_USERINFO_URL="${COGNITO_USERINFO_URL:-}"

# Client IDs
export IDENTITY_CLIENT_ID="${IDENTITY_CLIENT_ID:-}"
export OPTIMIZE_CLIENT_ID="${OPTIMIZE_CLIENT_ID:-}"
export ORCHESTRATION_CLIENT_ID="${ORCHESTRATION_CLIENT_ID:-}"
export CONNECTORS_CLIENT_ID="${CONNECTORS_CLIENT_ID:-}"
export CONSOLE_CLIENT_ID="${CONSOLE_CLIENT_ID:-}"
export WEBMODELER_UI_CLIENT_ID="${WEBMODELER_UI_CLIENT_ID:-}"
export WEBMODELER_API_CLIENT_ID="${WEBMODELER_API_CLIENT_ID:-}"

# Validate that required variables are set
if [ -z "$COGNITO_ISSUER_URL" ] || [ -z "$IDENTITY_CLIENT_ID" ]; then
    echo "⚠️  Warning: Required Cognito variables are not set"
    echo "Required: COGNITO_ISSUER_URL, IDENTITY_CLIENT_ID"
fi
