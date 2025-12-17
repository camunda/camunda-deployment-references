#!/bin/bash
# =============================================================================
# Orchestration Migration - Step 0: Introspect Elasticsearch
# =============================================================================
# This script introspects the current Bitnami Elasticsearch installation
# and exports configuration for use in subsequent migration steps.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../../shared"
MIGRATION_STATE_DIR="${SCRIPT_DIR}/.state"

# Source shared functions
# shellcheck source=/dev/null
source "${SHARED_DIR}/introspect-elasticsearch.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  Orchestration Migration - Step 0: Introspect Elasticsearch"
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

echo "Namespace: ${CAMUNDA_NAMESPACE}"
echo "Release: ${CAMUNDA_RELEASE_NAME}"
echo ""

# Create state directory
mkdir -p "${MIGRATION_STATE_DIR}"

# Introspect Elasticsearch
echo -e "${BLUE}=== Introspecting Elasticsearch ===${NC}"
echo ""

introspect_elasticsearch "elasticsearch" "${CAMUNDA_NAMESPACE}"

# Get credentials
echo ""
echo -e "${BLUE}=== Extracting Credentials ===${NC}"
echo ""

get_elasticsearch_credentials "${CAMUNDA_RELEASE_NAME}" "${CAMUNDA_NAMESPACE}"

# Save state for subsequent scripts
echo ""
echo -e "${BLUE}=== Saving Configuration ===${NC}"
echo ""

cat > "${MIGRATION_STATE_DIR}/elasticsearch.env" << EOF
# Elasticsearch introspection results
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

export ES_IMAGE="${ES_IMAGE}"
export ES_IMAGE_PULL_SECRETS="${ES_IMAGE_PULL_SECRETS:-}"
export ES_STORAGE_CLASS="${ES_STORAGE_CLASS}"
export ES_STORAGE_SIZE="${ES_STORAGE_SIZE}"
export ES_REPLICAS="${ES_REPLICAS}"
export ES_CPU_LIMIT="${ES_CPU_LIMIT}"
export ES_MEMORY_LIMIT="${ES_MEMORY_LIMIT}"
export ES_CPU_REQUEST="${ES_CPU_REQUEST}"
export ES_MEMORY_REQUEST="${ES_MEMORY_REQUEST}"
export ES_JAVA_OPTS="${ES_JAVA_OPTS:-}"
export ES_VERSION="${ES_VERSION}"
export ES_STS_NAME="${ES_STS_NAME}"
export ES_PASSWORD="${ES_PASSWORD:-}"
export ES_USERNAME="${ES_USERNAME:-elastic}"
EOF

echo -e "${GREEN}✓ Configuration saved to: ${MIGRATION_STATE_DIR}/elasticsearch.env${NC}"
echo ""

# Generate ECK manifest
echo -e "${BLUE}=== Generating ECK Cluster Manifest ===${NC}"
echo ""

generate_eck_cluster_manifest "camunda-elasticsearch" "${MIGRATION_STATE_DIR}/eck-cluster.yml"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Introspection Complete!${NC}"
echo "============================================================================="
echo ""
echo "Configuration saved to: ${MIGRATION_STATE_DIR}/"
echo ""
echo "Next step: ./1-backup.sh"
echo ""
