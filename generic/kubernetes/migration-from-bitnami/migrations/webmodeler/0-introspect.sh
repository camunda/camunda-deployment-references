#!/bin/bash
# =============================================================================
# WebModeler Migration - Step 0: Introspect WebModeler PostgreSQL
# =============================================================================
# This script introspects the current WebModeler PostgreSQL installation and
# checks if migration is needed (skip if not deployed or using external DB).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../../shared"
MIGRATION_STATE_DIR="${SCRIPT_DIR}/.state"

# Source shared functions
# shellcheck source=/dev/null
source "${SHARED_DIR}/introspect-postgres.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  WebModeler Migration - Step 0: Introspect Configuration"
echo "============================================================================="
echo ""

# Check environment
if [[ -z "${CAMUNDA_NAMESPACE:-}" ]]; then
    echo -e "${YELLOW}CAMUNDA_NAMESPACE not set, using 'camunda'${NC}"
    export CAMUNDA_NAMESPACE="camunda"
fi

if [[ -z "${CAMUNDA_RELEASE_NAME:-}" ]]; then
    echo -e "${YELLOW}CAMUNDA_RELEASE_NAME not set, using 'camunda'${NC}"
    export CAMUNDA_RELEASE_NAME="camunda"
fi

NAMESPACE="${CAMUNDA_NAMESPACE}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

# Create state directory
mkdir -p "${MIGRATION_STATE_DIR}"

# Remove any previous skip flag
rm -f "${MIGRATION_STATE_DIR}/skip"

# =============================================================================
# Step 1: Check if WebModeler is deployed
# =============================================================================
echo -e "${BLUE}=== Checking WebModeler Deployment ===${NC}"
echo ""

WEBMODELER_RESTAPI="${RELEASE_NAME}-web-modeler-restapi"
WEBMODELER_WEBAPP="${RELEASE_NAME}-web-modeler-webapp"
WEBMODELER_WEBSOCKETS="${RELEASE_NAME}-web-modeler-websockets"

# Check for any WebModeler component
WEBMODELER_FOUND=false

if kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${GREEN}✓ Found WebModeler RestAPI deployment${NC}"
    WEBMODELER_FOUND=true
fi

if kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${GREEN}✓ Found WebModeler Webapp deployment${NC}"
    WEBMODELER_FOUND=true
fi

if kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${GREEN}✓ Found WebModeler WebSockets deployment${NC}"
    WEBMODELER_FOUND=true
fi

if [[ "${WEBMODELER_FOUND}" != "true" ]]; then
    echo -e "${YELLOW}✓ WebModeler components not found - migration not needed${NC}"
    echo "SKIP_REASON=webmodeler_not_deployed" > "${MIGRATION_STATE_DIR}/skip"
    echo ""
    echo "WebModeler component is not deployed in this installation."
    echo "No migration is required."
    exit 0
fi

echo ""

# =============================================================================
# Step 2: Check if using Bitnami PostgreSQL (vs external)
# =============================================================================
echo -e "${BLUE}=== Checking PostgreSQL Mode ===${NC}"
echo ""

PG_STS_NAME=""

# Check for Bitnami WebModeler PostgreSQL StatefulSet
# The chart uses different naming conventions, try multiple patterns
if kubectl get statefulset "${RELEASE_NAME}-web-modeler-postgresql" -n "${NAMESPACE}" &>/dev/null; then
    PG_STS_NAME="${RELEASE_NAME}-web-modeler-postgresql"
elif kubectl get statefulset "${RELEASE_NAME}-webmodeler-postgresql" -n "${NAMESPACE}" &>/dev/null; then
    PG_STS_NAME="${RELEASE_NAME}-webmodeler-postgresql"
elif kubectl get statefulset -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/component=web-modeler" -n "${NAMESPACE}" -o name 2>/dev/null | head -1 | grep -q .; then
    PG_STS_NAME=$(kubectl get statefulset -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/component=web-modeler" -n "${NAMESPACE}" -o name 2>/dev/null | head -1 | sed 's|statefulset.apps/||')
fi

if [[ -z "$PG_STS_NAME" ]]; then
    echo -e "${YELLOW}✓ Bitnami PostgreSQL StatefulSet not found - migration not needed${NC}"
    echo "SKIP_REASON=external_postgresql" > "${MIGRATION_STATE_DIR}/skip"
    echo ""
    echo "WebModeler uses external PostgreSQL (managed separately)."
    echo "No PostgreSQL migration is required."
    exit 0
fi

echo -e "${GREEN}✓ Found Bitnami PostgreSQL StatefulSet: ${PG_STS_NAME}${NC}"
echo ""

# =============================================================================
# Step 3: Introspect PostgreSQL Configuration
# =============================================================================
echo -e "${BLUE}=== Introspecting PostgreSQL ===${NC}"
echo ""

introspect_postgres "${PG_STS_NAME}" "${NAMESPACE}"

# Get PostgreSQL credentials
get_postgres_credentials "${PG_STS_NAME}" "${NAMESPACE}"

echo ""

# =============================================================================
# Step 4: Detect PostgreSQL Version
# =============================================================================
echo -e "${BLUE}=== Detecting PostgreSQL Version ===${NC}"
echo ""

# Extract version from image tag
PG_VERSION=""
if [[ "${PG_IMAGE}" =~ :([0-9]+\.[0-9]+) ]]; then
    PG_VERSION="${BASH_REMATCH[1]}"
elif [[ "${PG_IMAGE}" =~ :([0-9]+) ]]; then
    PG_VERSION="${BASH_REMATCH[1]}"
fi

if [[ -n "${PG_VERSION}" ]]; then
    echo -e "${GREEN}✓ PostgreSQL version detected: ${PG_VERSION}${NC}"
else
    echo -e "${YELLOW}⚠ Could not detect PostgreSQL version from image tag${NC}"
    echo "  Image: ${PG_IMAGE}"
    PG_VERSION="unknown"
fi

echo ""

# =============================================================================
# Step 5: Check Resource Quotas (Warning)
# =============================================================================
echo -e "${BLUE}=== Resource Check ===${NC}"
echo ""

echo -e "${YELLOW}ℹ️  Note: Migration requires temporarily running both Bitnami and target PostgreSQL.${NC}"
echo "    Current PostgreSQL resources:"
echo "      CPU Request: ${PG_CPU_REQUEST}"
echo "      Memory Request: ${PG_MEMORY_REQUEST}"
echo ""
echo "    Ensure your cluster has sufficient capacity for dual-stack operation."
echo ""

# =============================================================================
# Step 6: Save State
# =============================================================================
echo -e "${BLUE}=== Saving Configuration ===${NC}"
echo ""

cat > "${MIGRATION_STATE_DIR}/webmodeler.env" << EOF
# WebModeler PostgreSQL introspection results
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

export PG_STS_NAME="${PG_STS_NAME}"
export PG_IMAGE="${PG_IMAGE}"
export PG_IMAGE_PULL_SECRETS="${PG_IMAGE_PULL_SECRETS:-}"
export PG_STORAGE_CLASS="${PG_STORAGE_CLASS}"
export PG_STORAGE_SIZE="${PG_STORAGE_SIZE}"
export PG_REPLICAS="${PG_REPLICAS}"
export PG_CPU_LIMIT="${PG_CPU_LIMIT}"
export PG_MEMORY_LIMIT="${PG_MEMORY_LIMIT}"
export PG_CPU_REQUEST="${PG_CPU_REQUEST}"
export PG_MEMORY_REQUEST="${PG_MEMORY_REQUEST}"
export PG_VERSION="${PG_VERSION}"

# Credentials
export PG_USERNAME="${PG_USERNAME:-postgres}"
export PG_PASSWORD="${PG_PASSWORD:-}"
export PG_DATABASE="${PG_DATABASE:-web-modeler}"

# WebModeler deployments
export WEBMODELER_RESTAPI="${WEBMODELER_RESTAPI}"
export WEBMODELER_WEBAPP="${WEBMODELER_WEBAPP}"
export WEBMODELER_WEBSOCKETS="${WEBMODELER_WEBSOCKETS}"
EOF

echo -e "${GREEN}✓ Configuration saved to ${MIGRATION_STATE_DIR}/webmodeler.env${NC}"
echo ""

echo "============================================================================="
echo -e "${GREEN}  Introspection Complete!${NC}"
echo "============================================================================="
echo ""
echo "Summary:"
echo "  PostgreSQL Image: ${PG_IMAGE}"
echo "  PostgreSQL Version: ${PG_VERSION}"
echo "  Storage: ${PG_STORAGE_SIZE} (${PG_STORAGE_CLASS})"
echo "  Database: ${PG_DATABASE:-web-modeler}"
echo ""
echo "Next step: ./1-backup.sh"
echo ""
