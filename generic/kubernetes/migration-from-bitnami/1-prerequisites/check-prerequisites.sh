#!/bin/bash

# =============================================================================
# Prerequisites Check Script
# =============================================================================
# This script validates that all prerequisites are met before starting migration
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../0-set-environment.sh" 2>/dev/null || true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

echo "============================================="
echo "Prerequisites Check"
echo "============================================="

# -----------------------------------------------------------------------------
# Check required CLI tools
# -----------------------------------------------------------------------------
echo ""
echo "Checking required CLI tools..."

check_command() {
    local cmd=$1
    local name=${2:-$1}
    if command -v "$cmd" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $name found: $(command -v "$cmd")"
    else
        echo -e "  ${RED}✗${NC} $name not found"
        ((ERRORS++))
    fi
}

check_command "kubectl" "kubectl"
check_command "helm" "helm"
check_command "jq" "jq"
check_command "envsubst" "envsubst"

# -----------------------------------------------------------------------------
# Check Kubernetes connectivity
# -----------------------------------------------------------------------------
echo ""
echo "Checking Kubernetes connectivity..."

if kubectl cluster-info &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Connected to Kubernetes cluster"
    kubectl cluster-info | head -1 | sed 's/^/    /'
else
    echo -e "  ${RED}✗${NC} Cannot connect to Kubernetes cluster"
    ((ERRORS++))
fi

# -----------------------------------------------------------------------------
# Check Kubernetes version
# -----------------------------------------------------------------------------
echo ""
echo "Checking Kubernetes version..."

K8S_VERSION=$(kubectl version --output=json 2>/dev/null | jq -r '.serverVersion.minor // "unknown"' | tr -d '+')
if [[ "$K8S_VERSION" != "unknown" && "$K8S_VERSION" -ge 24 ]]; then
    echo -e "  ${GREEN}✓${NC} Kubernetes version: 1.$K8S_VERSION (>= 1.24 required)"
else
    echo -e "  ${YELLOW}!${NC} Kubernetes version: 1.$K8S_VERSION (1.24+ recommended)"
fi

# -----------------------------------------------------------------------------
# Check namespace exists
# -----------------------------------------------------------------------------
echo ""
echo "Checking Camunda namespace..."

if kubectl get namespace "$CAMUNDA_NAMESPACE" &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Namespace '$CAMUNDA_NAMESPACE' exists"
else
    echo -e "  ${RED}✗${NC} Namespace '$CAMUNDA_NAMESPACE' not found"
    ((ERRORS++))
fi

# -----------------------------------------------------------------------------
# Check Helm release exists
# -----------------------------------------------------------------------------
echo ""
echo "Checking Camunda Helm release..."

if helm status "$CAMUNDA_RELEASE_NAME" -n "$CAMUNDA_NAMESPACE" &> /dev/null; then
    HELM_CHART_VERSION=$(helm get metadata "$CAMUNDA_RELEASE_NAME" -n "$CAMUNDA_NAMESPACE" -o json | jq -r '.chart')
    echo -e "  ${GREEN}✓${NC} Helm release '$CAMUNDA_RELEASE_NAME' found: $HELM_CHART_VERSION"
else
    echo -e "  ${RED}✗${NC} Helm release '$CAMUNDA_RELEASE_NAME' not found in namespace '$CAMUNDA_NAMESPACE'"
    ((ERRORS++))
fi

# -----------------------------------------------------------------------------
# Check Bitnami PostgreSQL
# -----------------------------------------------------------------------------
echo ""
echo "Checking Bitnami PostgreSQL components..."

check_pod() {
    local selector=$1
    local description=$2
    local pod_count
    pod_count=$(kubectl get pods -n "$CAMUNDA_NAMESPACE" -l "$selector" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$pod_count" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} $description ($pod_count pod(s))"
        return 0
    else
        echo -e "  ${YELLOW}!${NC} $description not found"
        return 1
    fi
}

# Check Keycloak PostgreSQL
check_pod "app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${CAMUNDA_RELEASE_NAME}-keycloak" \
    "Keycloak PostgreSQL" || true

# Check Identity PostgreSQL (may share with Keycloak)
check_pod "app.kubernetes.io/name=postgresql" \
    "PostgreSQL pods" || true

# -----------------------------------------------------------------------------
# Check Bitnami Elasticsearch
# -----------------------------------------------------------------------------
echo ""
echo "Checking Bitnami Elasticsearch..."

check_pod "app.kubernetes.io/name=elasticsearch" \
    "Elasticsearch" || true

# -----------------------------------------------------------------------------
# Check Bitnami Keycloak
# -----------------------------------------------------------------------------
echo ""
echo "Checking Bitnami Keycloak..."

check_pod "app.kubernetes.io/name=keycloak" \
    "Keycloak" || true

# -----------------------------------------------------------------------------
# Check storage class
# -----------------------------------------------------------------------------
echo ""
echo "Checking storage classes..."

STORAGE_CLASSES=$(kubectl get storageclass -o json | jq -r '.items[].metadata.name')
if [[ -n "$STORAGE_CLASSES" ]]; then
    echo -e "  ${GREEN}✓${NC} Storage classes available:"
    echo "$STORAGE_CLASSES" | while read -r sc; do
        DEFAULT=$(kubectl get storageclass "$sc" -o json | jq -r '.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "false"')
        if [[ "$DEFAULT" == "true" ]]; then
            echo "      - $sc (default)"
        else
            echo "      - $sc"
        fi
    done
else
    echo -e "  ${YELLOW}!${NC} No storage classes found"
fi

# -----------------------------------------------------------------------------
# Check available resources
# -----------------------------------------------------------------------------
echo ""
echo "Checking cluster resources..."

NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
echo "  Nodes: $NODE_COUNT"

TOTAL_CPU=$(kubectl get nodes -o json | jq '[.items[].status.allocatable.cpu | gsub("m"; "") | tonumber] | add')
TOTAL_MEMORY=$(kubectl get nodes -o json | jq '[.items[].status.allocatable.memory | gsub("Ki"; "") | tonumber] | add / 1024 / 1024 | floor')
echo "  Total allocatable CPU: ~${TOTAL_CPU}m"
echo "  Total allocatable Memory: ~${TOTAL_MEMORY}Gi"

echo ""
echo -e "  ${YELLOW}!${NC} Note: Migration requires approximately 2x current resource usage"
echo "      during the dual-stack phase"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}Prerequisites check FAILED with $ERRORS error(s)${NC}"
    echo "Please fix the issues above before proceeding."
    exit 1
else
    echo -e "${GREEN}Prerequisites check PASSED${NC}"
    echo "You can proceed with the migration."
    exit 0
fi
