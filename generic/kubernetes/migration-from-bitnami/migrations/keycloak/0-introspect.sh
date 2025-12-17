#!/bin/bash
# =============================================================================
# Keycloak Migration - Step 0: Introspect Keycloak Configuration
# =============================================================================
# This script introspects the current Bitnami Keycloak installation and
# detects whether PostgreSQL is integrated (Bitnami sub-chart) or external.
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
echo "  Keycloak Migration - Step 0: Introspect Configuration"
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

# =============================================================================
# Step 1: Check if Keycloak is deployed
# =============================================================================
echo -e "${BLUE}=== Checking Keycloak Deployment ===${NC}"
echo ""

KEYCLOAK_STS_NAME=""

# Try to find Keycloak StatefulSet (Bitnami uses StatefulSet)
if kubectl get statefulset "${RELEASE_NAME}-keycloak" -n "${NAMESPACE}" &>/dev/null; then
    KEYCLOAK_STS_NAME="${RELEASE_NAME}-keycloak"
elif kubectl get statefulset -l "app.kubernetes.io/name=keycloak" -n "${NAMESPACE}" -o name 2>/dev/null | head -1 | grep -q .; then
    KEYCLOAK_STS_NAME=$(kubectl get statefulset -l "app.kubernetes.io/name=keycloak" -n "${NAMESPACE}" -o name 2>/dev/null | head -1 | sed 's|statefulset.apps/||')
fi

if [[ -z "$KEYCLOAK_STS_NAME" ]]; then
    echo -e "${YELLOW}✓ Keycloak StatefulSet not found - Keycloak migration not needed${NC}"
    echo "SKIP_REASON=keycloak_not_deployed" > "${MIGRATION_STATE_DIR}/skip"
    echo ""
    echo "If Keycloak is deployed differently, check your installation."
    exit 0
fi

echo -e "${GREEN}✓ Found Keycloak StatefulSet: ${KEYCLOAK_STS_NAME}${NC}"
echo ""

# =============================================================================
# Step 2: Introspect Keycloak Configuration
# =============================================================================
echo -e "${BLUE}=== Introspecting Keycloak ===${NC}"
echo ""

# Get Keycloak StatefulSet JSON
KC_JSON=$(kubectl get statefulset "${KEYCLOAK_STS_NAME}" -n "${NAMESPACE}" -o json)

# Extract Keycloak image
KC_IMAGE=$(echo "$KC_JSON" | jq -r '.spec.template.spec.containers[0].image')
echo -e "${GREEN}✓ Keycloak Image:${NC} ${KC_IMAGE}"

# Extract imagePullSecrets
KC_IMAGE_PULL_SECRETS=$(echo "$KC_JSON" | jq -r '.spec.template.spec.imagePullSecrets // [] | .[].name' | tr '\n' ',' | sed 's/,$//')
if [[ -n "$KC_IMAGE_PULL_SECRETS" ]]; then
    echo -e "${GREEN}✓ ImagePullSecrets:${NC} ${KC_IMAGE_PULL_SECRETS}"
else
    echo -e "${YELLOW}⚠ No ImagePullSecrets found${NC}"
fi

# Extract replica count
KC_REPLICAS=$(echo "$KC_JSON" | jq -r '.spec.replicas // 1')
echo -e "${GREEN}✓ Replicas:${NC} ${KC_REPLICAS}"

# Extract resources
KC_CPU_REQUEST=$(echo "$KC_JSON" | jq -r '.spec.template.spec.containers[0].resources.requests.cpu // "250m"')
KC_MEMORY_REQUEST=$(echo "$KC_JSON" | jq -r '.spec.template.spec.containers[0].resources.requests.memory // "512Mi"')
KC_CPU_LIMIT=$(echo "$KC_JSON" | jq -r '.spec.template.spec.containers[0].resources.limits.cpu // "1"')
KC_MEMORY_LIMIT=$(echo "$KC_JSON" | jq -r '.spec.template.spec.containers[0].resources.limits.memory // "1Gi"')

echo -e "${GREEN}✓ Resources:${NC}"
echo "    CPU: ${KC_CPU_REQUEST} / ${KC_CPU_LIMIT}"
echo "    Memory: ${KC_MEMORY_REQUEST} / ${KC_MEMORY_LIMIT}"

# Extract Keycloak version from image tag
KC_VERSION=$(echo "$KC_IMAGE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "26.0.0")
echo -e "${GREEN}✓ Keycloak Version:${NC} ${KC_VERSION}"

echo ""

# =============================================================================
# Step 3: Detect Custom Volumes (Themes, SPIs)
# =============================================================================
echo -e "${BLUE}=== Checking for Custom Volumes ===${NC}"
echo ""

CUSTOM_VOLUMES=$(echo "$KC_JSON" | jq -r '.spec.template.spec.volumes // [] | .[] | select(.name != "data" and .name != "tmp" and .name != "empty-dir") | .name' | tr '\n' ',' | sed 's/,$//')
CUSTOM_MOUNTS=$(echo "$KC_JSON" | jq -r '.spec.template.spec.containers[0].volumeMounts // [] | .[] | select(.name != "data" and .name != "tmp" and .name != "empty-dir") | "\(.name):\(.mountPath)"' | tr '\n' ';' | sed 's/;$//')

if [[ -n "$CUSTOM_VOLUMES" ]]; then
    echo -e "${YELLOW}⚠ Custom volumes detected: ${CUSTOM_VOLUMES}${NC}"
    echo -e "${YELLOW}  Volume mounts: ${CUSTOM_MOUNTS}${NC}"
    echo ""
    echo -e "${YELLOW}  WARNING: These may contain Themes or SPI providers that need${NC}"
    echo -e "${YELLOW}  manual migration to the Keycloak Operator CRD.${NC}"
    echo ""
    KC_HAS_CUSTOM_VOLUMES="true"
else
    echo -e "${GREEN}✓ No custom volumes detected${NC}"
    KC_HAS_CUSTOM_VOLUMES="false"
fi
echo ""

# =============================================================================
# Step 4: Detect PostgreSQL Mode (Integrated vs External)
# =============================================================================
echo -e "${BLUE}=== Detecting PostgreSQL Mode ===${NC}"
echo ""

PG_MODE="external"
PG_STS_NAME=""

# Check for Bitnami Keycloak PostgreSQL StatefulSet
if kubectl get statefulset "${RELEASE_NAME}-keycloak-postgresql" -n "${NAMESPACE}" &>/dev/null; then
    PG_STS_NAME="${RELEASE_NAME}-keycloak-postgresql"
    PG_MODE="integrated"
elif kubectl get statefulset -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${RELEASE_NAME}-keycloak" -n "${NAMESPACE}" -o name 2>/dev/null | head -1 | grep -q .; then
    PG_STS_NAME=$(kubectl get statefulset -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${RELEASE_NAME}-keycloak" -n "${NAMESPACE}" -o name 2>/dev/null | head -1 | sed 's|statefulset.apps/||')
    PG_MODE="integrated"
fi

if [[ "$PG_MODE" == "integrated" ]]; then
    echo -e "${GREEN}✓ PostgreSQL Mode: INTEGRATED (Bitnami sub-chart)${NC}"
    echo -e "${GREEN}✓ PostgreSQL StatefulSet: ${PG_STS_NAME}${NC}"
    echo ""

    # Introspect PostgreSQL
    echo -e "${BLUE}=== Introspecting PostgreSQL ===${NC}"
    echo ""
    introspect_postgres "${PG_STS_NAME}" "${NAMESPACE}"

    # Get PostgreSQL credentials
    get_postgres_credentials "${RELEASE_NAME}-keycloak-postgresql" "${NAMESPACE}"

    # Save PostgreSQL state
    cat > "${MIGRATION_STATE_DIR}/postgres.env" << EOF
# PostgreSQL introspection results
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

export KC_PG_STS_NAME="${KC_PG_STS_NAME}"
export KC_PG_IMAGE="${KC_PG_IMAGE}"
export KC_PG_IMAGE_PULL_SECRETS="${KC_PG_IMAGE_PULL_SECRETS:-}"
export KC_PG_STORAGE_CLASS="${KC_PG_STORAGE_CLASS}"
export KC_PG_STORAGE_SIZE="${KC_PG_STORAGE_SIZE}"
export KC_PG_REPLICAS="${KC_PG_REPLICAS}"
export KC_PG_CPU_LIMIT="${KC_PG_CPU_LIMIT}"
export KC_PG_MEMORY_LIMIT="${KC_PG_MEMORY_LIMIT}"
export KC_PG_CPU_REQUEST="${KC_PG_CPU_REQUEST}"
export KC_PG_MEMORY_REQUEST="${KC_PG_MEMORY_REQUEST}"
export KC_PG_VERSION="${KC_PG_VERSION}"
export KC_PG_PASSWORD="${KC_PG_PASSWORD:-}"
export KC_PG_USERNAME="${KC_PG_USERNAME:-postgres}"
export KC_PG_DATABASE="${KEYCLOAK_DB_NAME:-keycloak}"
EOF
    echo ""
    echo -e "${GREEN}✓ PostgreSQL configuration saved to: ${MIGRATION_STATE_DIR}/postgres.env${NC}"

else
    echo -e "${GREEN}✓ PostgreSQL Mode: EXTERNAL${NC}"
    echo ""
    echo "Keycloak uses an external PostgreSQL database."
    echo "Only Keycloak application will be migrated, database remains unchanged."

    # Try to extract external PostgreSQL connection info from Keycloak env vars
    echo ""
    echo -e "${BLUE}=== Extracting External PostgreSQL Connection Info ===${NC}"
    echo ""

    # Get DB host from Keycloak environment
    EXT_PG_HOST=$(echo "$KC_JSON" | jq -r '.spec.template.spec.containers[0].env[] | select(.name == "KC_DB_URL_HOST" or .name == "KEYCLOAK_JDBC_URL" or .name == "KC_DB_URL") | .value' | head -1 || echo "")

    if [[ -n "$EXT_PG_HOST" ]]; then
        echo -e "${GREEN}✓ External PostgreSQL Host:${NC} ${EXT_PG_HOST}"
    else
        echo -e "${YELLOW}⚠ Could not detect external PostgreSQL host from environment${NC}"
        echo "  You will need to provide connection details during deployment."
    fi
fi

echo ""

# =============================================================================
# Step 5: Save Keycloak State
# =============================================================================
echo -e "${BLUE}=== Saving Keycloak Configuration ===${NC}"
echo ""

cat > "${MIGRATION_STATE_DIR}/keycloak.env" << EOF
# Keycloak introspection results
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

export KC_STS_NAME="${KEYCLOAK_STS_NAME}"
export KC_IMAGE="${KC_IMAGE}"
export KC_IMAGE_PULL_SECRETS="${KC_IMAGE_PULL_SECRETS:-}"
export KC_REPLICAS="${KC_REPLICAS}"
export KC_CPU_LIMIT="${KC_CPU_LIMIT}"
export KC_MEMORY_LIMIT="${KC_MEMORY_LIMIT}"
export KC_CPU_REQUEST="${KC_CPU_REQUEST}"
export KC_MEMORY_REQUEST="${KC_MEMORY_REQUEST}"
export KC_VERSION="${KC_VERSION}"
export KC_HAS_CUSTOM_VOLUMES="${KC_HAS_CUSTOM_VOLUMES}"
export KC_CUSTOM_VOLUMES="${CUSTOM_VOLUMES:-}"
export KC_CUSTOM_MOUNTS="${CUSTOM_MOUNTS:-}"

# PostgreSQL mode
export PG_MODE="${PG_MODE}"
EOF

echo -e "${GREEN}✓ Keycloak configuration saved to: ${MIGRATION_STATE_DIR}/keycloak.env${NC}"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Introspection Complete!${NC}"
echo "============================================================================="
echo ""
echo "PostgreSQL Mode: ${PG_MODE^^}"
if [[ "$KC_HAS_CUSTOM_VOLUMES" == "true" ]]; then
    echo -e "${YELLOW}⚠ Custom volumes detected - manual CRD adjustment may be required${NC}"
fi
echo ""
echo "Configuration saved to: ${MIGRATION_STATE_DIR}/"
echo ""
echo "Next step: ./1-backup.sh"
echo ""
