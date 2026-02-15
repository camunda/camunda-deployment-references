#!/bin/bash
# =============================================================================
# Migration Environment Configuration
# =============================================================================
# Source this file to set all required environment variables.
# Override any variable before sourcing to customise for your setup.
#
# Usage: source env.sh
# =============================================================================

# ---[ Namespace & Helm ]------------------------------------------------------
export NAMESPACE="${NAMESPACE:-camunda}"
export CAMUNDA_RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"

# renovate: datasource=helm depName=camunda-platform registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="${CAMUNDA_HELM_CHART_VERSION:-0.0.0-snapshot-alpha}"

# ---[ Operator versions ]-----------------------------------------------------
# NOTE: Operator versions are managed by the deploy scripts in operator-based/.
# These are kept here for reference only. To change versions, edit:
#   operator-based/postgresql/deploy.sh   → CNPG_VERSION
#   operator-based/elasticsearch/deploy.sh → ECK_VERSION
#   operator-based/keycloak/deploy.sh      → KEYCLOAK_VERSION

# ---[ Operator namespaces ]---------------------------------------------------
export CNPG_OPERATOR_NAMESPACE="${CNPG_OPERATOR_NAMESPACE:-cnpg-system}"
export ECK_OPERATOR_NAMESPACE="${ECK_OPERATOR_NAMESPACE:-elastic-system}"

# ---[ Camunda domain (for Keycloak Ingress) ]---------------------------------
# Set to a real domain to generate Keycloak Ingress + TLS.
# Leave empty or "localhost" for port-forward setups.
export CAMUNDA_DOMAIN="${CAMUNDA_DOMAIN:-}"

# ---[ CNPG target cluster names ]---------------------------------------------
export CNPG_IDENTITY_CLUSTER="${CNPG_IDENTITY_CLUSTER:-pg-identity}"
export CNPG_KEYCLOAK_CLUSTER="${CNPG_KEYCLOAK_CLUSTER:-pg-keycloak}"
export CNPG_WEBMODELER_CLUSTER="${CNPG_WEBMODELER_CLUSTER:-pg-webmodeler}"

# ---[ ECK target cluster name ]-----------------------------------------------
export ECK_CLUSTER_NAME="${ECK_CLUSTER_NAME:-elasticsearch}"

# ---[ Database names (must match source installation) ]-----------------------
export IDENTITY_DB_NAME="${IDENTITY_DB_NAME:-identity}"
export IDENTITY_DB_USER="${IDENTITY_DB_USER:-identity}"
export KEYCLOAK_DB_NAME="${KEYCLOAK_DB_NAME:-keycloak}"
export KEYCLOAK_DB_USER="${KEYCLOAK_DB_USER:-keycloak}"
export WEBMODELER_DB_NAME="${WEBMODELER_DB_NAME:-webmodeler}"
export WEBMODELER_DB_USER="${WEBMODELER_DB_USER:-webmodeler}"

# ---[ Backup configuration ]-------------------------------------------------
export BACKUP_PVC="${BACKUP_PVC:-migration-backup-pvc}"
export BACKUP_STORAGE_SIZE="${BACKUP_STORAGE_SIZE:-50Gi}"

# ---[ Which components to migrate ]-------------------------------------------
# Set to "false" to skip a component entirely.
export MIGRATE_IDENTITY="${MIGRATE_IDENTITY:-true}"
export MIGRATE_KEYCLOAK="${MIGRATE_KEYCLOAK:-true}"
export MIGRATE_WEBMODELER="${MIGRATE_WEBMODELER:-true}"
export MIGRATE_ELASTICSEARCH="${MIGRATE_ELASTICSEARCH:-true}"

# ---[ Target mode ]-----------------------------------------------------------
# "operator" (default): deploy CNPG/ECK operators + cluster instances in-cluster
# "external": migrate data to a managed service (e.g. AWS RDS, OpenSearch, etc.)
#             Operators are NOT deployed — only data migration + helm switch.
export PG_TARGET_MODE="${PG_TARGET_MODE:-operator}"
export ES_TARGET_MODE="${ES_TARGET_MODE:-operator}"

# ---[ External PostgreSQL targets (PG_TARGET_MODE=external) ]-----------------
# The same host can be used for all components (different databases on one RDS).
# Each Kubernetes secret must contain a 'password' key.
export EXTERNAL_PG_IDENTITY_HOST="${EXTERNAL_PG_IDENTITY_HOST:-}"
export EXTERNAL_PG_IDENTITY_PORT="${EXTERNAL_PG_IDENTITY_PORT:-5432}"
export EXTERNAL_PG_IDENTITY_SECRET="${EXTERNAL_PG_IDENTITY_SECRET:-external-pg-identity}"
export EXTERNAL_PG_KEYCLOAK_HOST="${EXTERNAL_PG_KEYCLOAK_HOST:-}"
export EXTERNAL_PG_KEYCLOAK_PORT="${EXTERNAL_PG_KEYCLOAK_PORT:-5432}"
export EXTERNAL_PG_KEYCLOAK_SECRET="${EXTERNAL_PG_KEYCLOAK_SECRET:-external-pg-keycloak}"
export EXTERNAL_PG_WEBMODELER_HOST="${EXTERNAL_PG_WEBMODELER_HOST:-}"
export EXTERNAL_PG_WEBMODELER_PORT="${EXTERNAL_PG_WEBMODELER_PORT:-5432}"
export EXTERNAL_PG_WEBMODELER_SECRET="${EXTERNAL_PG_WEBMODELER_SECRET:-external-pg-webmodeler}"

# ---[ External ES/OpenSearch target (ES_TARGET_MODE=external) ]---------------
# NOTE: Automated ES data migration is NOT supported for external targets
#       (filesystem snapshots require shared storage with the ES process).
#       Only operator deployment is skipped and helm is reconfigured.
#       For data transfer options, see the migration README.
export EXTERNAL_ES_HOST="${EXTERNAL_ES_HOST:-}"
export EXTERNAL_ES_PORT="${EXTERNAL_ES_PORT:-443}"
export EXTERNAL_ES_SECRET="${EXTERNAL_ES_SECRET:-external-es}"

# ---[ Custom Helm values ]----------------------------------------------------
# Path to a custom helm values file for external service connections.
# Required when PG_TARGET_MODE=external or ES_TARGET_MODE=external.
# This file should configure database URLs, credentials, and ES endpoints
# to point Camunda at the managed service(s).
export CUSTOM_HELM_VALUES_FILE="${CUSTOM_HELM_VALUES_FILE:-}"

# ---[ Custom Keycloak CR ]----------------------------------------------------
# When PG_TARGET_MODE=external and MIGRATE_KEYCLOAK=true, the Keycloak CR
# must be customized to point to the external PG (instead of CNPG cluster).
# Provide a custom Keycloak CR file here (overrides automatic selection).
export CUSTOM_KEYCLOAK_CONFIG_FILE="${CUSTOM_KEYCLOAK_CONFIG_FILE:-}"

# =============================================================================
echo "Migration config loaded:"
echo "  Namespace:    ${NAMESPACE}"
echo "  Release:      ${CAMUNDA_RELEASE_NAME}"
echo "  Chart:        ${CAMUNDA_HELM_CHART_VERSION}"
echo "  Domain:       ${CAMUNDA_DOMAIN:-<none>}"
echo "  Components:   identity=${MIGRATE_IDENTITY} keycloak=${MIGRATE_KEYCLOAK} webmodeler=${MIGRATE_WEBMODELER} elasticsearch=${MIGRATE_ELASTICSEARCH}"
if [[ "${PG_TARGET_MODE}" == "external" ]]; then
    echo "  PG target:    external (${EXTERNAL_PG_IDENTITY_HOST:-<not set>})"
else
    echo "  PG target:    operator"
fi
if [[ "${ES_TARGET_MODE}" == "external" ]]; then
    echo "  ES target:    external (${EXTERNAL_ES_HOST:-<not set>})"
else
    echo "  ES target:    operator"
fi
echo ""
