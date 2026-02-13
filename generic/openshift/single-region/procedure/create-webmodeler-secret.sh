#!/bin/bash
# Create secrets for Web Modeler configuration:
# - webmodeler-secret: SMTP password for email delivery
# - webmodeler-postgresql-secret: credentials for the embedded PostgreSQL subchart

set -euo pipefail

# Modify this value to set your SMTP password
SMTP_PASSWORD="${SMTP_PASSWORD:-}"

oc create secret generic webmodeler-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=smtp-password="$SMTP_PASSWORD" \
  --dry-run=client -o yaml | oc apply -f -

# Create the PostgreSQL secret for the embedded webModelerPostgresql subchart.
# This is required because the chart template references
# webModelerPostgresql.auth.existingSecret without a default fallback.
WEBMODELER_DB_ADMIN_PASSWORD="${WEBMODELER_DB_ADMIN_PASSWORD:-$(openssl rand -base64 24)}"
WEBMODELER_DB_USER_PASSWORD="${WEBMODELER_DB_USER_PASSWORD:-$(openssl rand -base64 24)}"

oc create secret generic webmodeler-postgresql-secret \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=webmodeler-postgresql-admin-password="$WEBMODELER_DB_ADMIN_PASSWORD" \
  --from-literal=webmodeler-postgresql-user-password="$WEBMODELER_DB_USER_PASSWORD" \
  --dry-run=client -o yaml | oc apply -f -
