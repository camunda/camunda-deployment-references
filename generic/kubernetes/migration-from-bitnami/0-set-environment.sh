#!/bin/bash

# =============================================================================
# Migration Environment Configuration
# =============================================================================
# Source this file to set the required environment variables for migration
# Usage: source 0-set-environment.sh
# =============================================================================

set -euo pipefail

# =============================================================================
# NAMESPACE CONFIGURATION
# =============================================================================

# Camunda namespace where the existing installation is running
export CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"

# Operator namespaces (where operators will be installed)
export CNPG_OPERATOR_NAMESPACE="${CNPG_OPERATOR_NAMESPACE:-cnpg-system}"
export ECK_OPERATOR_NAMESPACE="${ECK_OPERATOR_NAMESPACE:-elastic-system}"

# =============================================================================
# HELM CONFIGURATION
# =============================================================================

# Camunda Helm release name (should match existing installation)
export CAMUNDA_RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"

# Camunda Helm chart version (8.9 for migration)
# renovate: datasource=helm depName=camunda-platform versioning=regex:^12(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="${CAMUNDA_HELM_CHART_VERSION:-0.0.0-snapshot-alpha}"

# =============================================================================
# BITNAMI SOURCE CONFIGURATION
# =============================================================================

# PostgreSQL Bitnami service names (adjust to match your installation)
export BITNAMI_KEYCLOAK_PG_SVC="${BITNAMI_KEYCLOAK_PG_SVC:-${CAMUNDA_RELEASE_NAME}-keycloak-postgresql}"
export BITNAMI_IDENTITY_PG_SVC="${BITNAMI_IDENTITY_PG_SVC:-${CAMUNDA_RELEASE_NAME}-postgresql}"
export BITNAMI_WEBMODELER_PG_SVC="${BITNAMI_WEBMODELER_PG_SVC:-${CAMUNDA_RELEASE_NAME}-postgresql-web-modeler}"

# Elasticsearch Bitnami service name
export BITNAMI_ES_SVC="${BITNAMI_ES_SVC:-${CAMUNDA_RELEASE_NAME}-elasticsearch}"

# Keycloak Bitnami service name
export BITNAMI_KEYCLOAK_SVC="${BITNAMI_KEYCLOAK_SVC:-${CAMUNDA_RELEASE_NAME}-keycloak}"

# =============================================================================
# OPERATOR TARGET CONFIGURATION
# =============================================================================

# CloudNativePG cluster names (targets)
export CNPG_KEYCLOAK_CLUSTER="${CNPG_KEYCLOAK_CLUSTER:-pg-keycloak}"
export CNPG_IDENTITY_CLUSTER="${CNPG_IDENTITY_CLUSTER:-pg-identity}"
export CNPG_WEBMODELER_CLUSTER="${CNPG_WEBMODELER_CLUSTER:-pg-webmodeler}"

# ECK Elasticsearch cluster name (target)
export ECK_ES_CLUSTER="${ECK_ES_CLUSTER:-elasticsearch}"

# Keycloak Operator instance name (target)
export KEYCLOAK_OPERATOR_INSTANCE="${KEYCLOAK_OPERATOR_INSTANCE:-keycloak}"

# =============================================================================
# OPERATOR VERSIONS
# =============================================================================

# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
export CNPG_VERSION="${CNPG_VERSION:-1.28.0}"

# renovate: datasource=github-releases depName=elastic/cloud-on-k8s
export ECK_VERSION="${ECK_VERSION:-3.2.0}"

# renovate: datasource=docker depName=camunda/keycloak versioning=regex:^quay-optimized-(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
export KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-26.3.2}"

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

# Database names (should match existing installation)
export KEYCLOAK_DB_NAME="${KEYCLOAK_DB_NAME:-keycloak}"
export IDENTITY_DB_NAME="${IDENTITY_DB_NAME:-identity}"
export WEBMODELER_DB_NAME="${WEBMODELER_DB_NAME:-webmodeler}"

# Database users
export KEYCLOAK_DB_USER="${KEYCLOAK_DB_USER:-keycloak}"
export IDENTITY_DB_USER="${IDENTITY_DB_USER:-identity}"
export WEBMODELER_DB_USER="${WEBMODELER_DB_USER:-webmodeler}"

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

# Backup directory (inside pods/jobs)
export BACKUP_DIR="${BACKUP_DIR:-/backup}"

# PVC name for storing backups
export BACKUP_PVC_NAME="${BACKUP_PVC_NAME:-migration-backup-pvc}"

# Backup storage size
export BACKUP_STORAGE_SIZE="${BACKUP_STORAGE_SIZE:-50Gi}"

# =============================================================================
# MIGRATION OPTIONS
# =============================================================================

# Components to migrate (set to "false" to skip)
export MIGRATE_POSTGRESQL="${MIGRATE_POSTGRESQL:-true}"
export MIGRATE_ELASTICSEARCH="${MIGRATE_ELASTICSEARCH:-true}"
export MIGRATE_KEYCLOAK="${MIGRATE_KEYCLOAK:-true}"

# Dry run mode (set to "true" to validate without making changes)
export DRY_RUN="${DRY_RUN:-false}"

# Rollback timeout in seconds
export ROLLBACK_TIMEOUT="${ROLLBACK_TIMEOUT:-900}"

# =============================================================================
# VALIDATION
# =============================================================================

echo "============================================="
echo "Migration Environment Configuration"
echo "============================================="
echo ""
echo "Namespace:           $CAMUNDA_NAMESPACE"
echo "Release Name:        $CAMUNDA_RELEASE_NAME"
echo "Chart Version:       $CAMUNDA_HELM_CHART_VERSION"
echo ""
echo "Bitnami Sources:"
echo "  - Keycloak PG:     $BITNAMI_KEYCLOAK_PG_SVC"
echo "  - Identity PG:     $BITNAMI_IDENTITY_PG_SVC"
echo "  - WebModeler PG:   $BITNAMI_WEBMODELER_PG_SVC"
echo "  - Elasticsearch:   $BITNAMI_ES_SVC"
echo "  - Keycloak:        $BITNAMI_KEYCLOAK_SVC"
echo ""
echo "Operator Targets:"
echo "  - CNPG Keycloak:   $CNPG_KEYCLOAK_CLUSTER"
echo "  - CNPG Identity:   $CNPG_IDENTITY_CLUSTER"
echo "  - CNPG WebModeler: $CNPG_WEBMODELER_CLUSTER"
echo "  - ECK ES:          $ECK_ES_CLUSTER"
echo "  - Keycloak:        $KEYCLOAK_OPERATOR_INSTANCE"
echo ""
echo "Operator Versions:"
echo "  - CNPG:            $CNPG_VERSION"
echo "  - ECK:             $ECK_VERSION"
echo "  - Keycloak:        $KEYCLOAK_VERSION"
echo ""
echo "Migration Options:"
echo "  - PostgreSQL:      $MIGRATE_POSTGRESQL"
echo "  - Elasticsearch:   $MIGRATE_ELASTICSEARCH"
echo "  - Keycloak:        $MIGRATE_KEYCLOAK"
echo "  - Dry Run:         $DRY_RUN"
echo "============================================="
