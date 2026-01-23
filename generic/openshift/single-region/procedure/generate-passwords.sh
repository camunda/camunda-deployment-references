#!/bin/bash

# Generate passwords for Camunda 8 components (production/OIDC mode)
#
# For embedded Keycloak (CI/Test), use instead:
#   source tests/procedure/generate-passwords.sh
#   source tests/procedure/generate-keycloak-passwords.sh
#   ./tests/procedure/create-keycloak-identity-secret.sh

# SMTP password for WebModeler (if enabled)
export SMTP_PASSWORD="${SMTP_PASSWORD:-}"
