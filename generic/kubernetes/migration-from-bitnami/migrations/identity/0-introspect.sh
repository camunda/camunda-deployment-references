#!/bin/bash
# =============================================================================
# Identity Migration - Step 0: Introspect Identity PostgreSQL
# =============================================================================
# This script introspects the current Identity PostgreSQL installation and
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
echo "  Identity Migration - Step 0: Introspect Configuration"
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
# Step 1: Check if Identity is deployed
# =============================================================================
echo -e "${BLUE}=== Checking Identity Deployment ===${NC}"
echo ""

IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"

if ! kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}✓ Identity deployment not found - migration not needed${NC}"
    echo "SKIP_REASON=identity_not_deployed" > "${MIGRATION_STATE_DIR}/skip"
    echo ""
    echo "Identity component is not deployed in this installation."
    echo "No migration is required."
    exit 0
fi

echo -e "${GREEN}✓ Found Identity deployment: ${IDENTITY_DEPLOYMENT}${NC}"
echo ""

# =============================================================================
# Step 2: Check if using Bitnami PostgreSQL (vs external)
# =============================================================================
echo -e "${BLUE}=== Checking PostgreSQL Mode ===${NC}"
echo ""

PG_STS_NAME=""

# Check for Bitnami Identity PostgreSQL StatefulSet
# The chart uses different naming conventions, try multiple patterns
if kubectl get statefulset "${RELEASE_NAME}-postgresql" -n "${NAMESPACE}" &>/dev/null; then
    PG_STS_NAME="${RELEASE_NAME}-postgresql"
elif kubectl get statefulset "${RELEASE_NAME}-identity-postgresql" -n "${NAMESPACE}" &>/dev/null; then
    PG_STS_NAME="${RELEASE_NAME}-identity-postgresql"
elif kubectl get statefulset -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${RELEASE_NAME}" -n "${NAMESPACE}" -o name 2>/dev/null | head -1 | grep -q .; then
    PG_STS_NAME=$(kubectl get statefulset -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${RELEASE_NAME}" -n "${NAMESPACE}" -o name 2>/dev/null | head -1 | sed 's|statefulset.apps/||')
fi

if [[ -z "$PG_STS_NAME" ]]; then
    echo -e "${YELLOW}✓ Bitnami PostgreSQL StatefulSet not found - migration not needed${NC}"
    echo "SKIP_REASON=external_postgresql" > "${MIGRATION_STATE_DIR}/skip"
    echo ""
    echo "Identity uses external PostgreSQL (managed separately)."
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
# Step 4: Check Resource Quotas (Warning)
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
# Step 5: Save State
# =============================================================================
echo -e "${BLUE}=== Saving Configuration ===${NC}"
echo ""

cat > "${MIGRATION_STATE_DIR}/identity.env" << EOF
# Identity PostgreSQL introspection results
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
export PG_PASSWORD="${PG_PASSWORD:-}"
export PG_USERNAME="${PG_USERNAME:-postgres}"
export PG_DATABASE="${IDENTITY_DB_NAME:-identity}"
EOF

echo -e "${GREEN}✓ Configuration saved to: ${MIGRATION_STATE_DIR}/identity.env${NC}"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Introspection Complete!${NC}"
echo "============================================================================="
echo ""
echo "PostgreSQL Image: ${PG_IMAGE}"
echo "PostgreSQL Version: ${PG_VERSION}"
echo "Storage: ${PG_STORAGE_SIZE} (${PG_STORAGE_CLASS})"
echo ""
echo "Next step: ./1-backup.sh"
echo ""
