#!/bin/bash
# Export OIDC environment variables for Helm chart installation
# This script is used in CI/CD to pass OIDC configuration to helm values

# These variables should be set by the CI system or manually before running this script

export OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-}"
export OIDC_AUTHORIZATION_URL="${OIDC_AUTHORIZATION_URL:-}"
export OIDC_TOKEN_URL="${OIDC_TOKEN_URL:-}"
export OIDC_JWKS_URL="${OIDC_JWKS_URL:-}"
export OIDC_USERINFO_URL="${OIDC_USERINFO_URL:-}"
export OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-}"
export OIDC_TENANT_ID="${OIDC_TENANT_ID:-}"

# Validate that required variables are set
if [ -z "$OIDC_ISSUER_URL" ] || [ -z "$OIDC_CLIENT_ID" ]; then
    echo "⚠️  Warning: Required OIDC variables are not set"
    echo "Required: OIDC_ISSUER_URL, OIDC_CLIENT_ID"
fi
