#!/bin/bash
# =============================================================================
# Shared PostgreSQL Introspection Script
# =============================================================================
# This script introspects a Bitnami PostgreSQL StatefulSet to extract:
# - Full image path (including private registry)
# - ImagePullSecrets
# - Storage class and size
# - Resource limits
# - Replica count
#
# Usage: source this script and call introspect_postgres <statefulset-name>
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Introspect PostgreSQL StatefulSet
# -----------------------------------------------------------------------------
# Arguments:
#   $1 - StatefulSet name
#   $2 - Namespace (optional, defaults to CAMUNDA_NAMESPACE)
#
# Exports:
#   PG_IMAGE - Full image path
#   PG_IMAGE_PULL_SECRETS - Comma-separated list of pull secrets
#   PG_STORAGE_CLASS - Storage class name
#   PG_STORAGE_SIZE - Storage size (e.g., 10Gi)
#   PG_REPLICAS - Number of replicas
#   PG_CPU_LIMIT - CPU limit
#   PG_MEMORY_LIMIT - Memory limit
#   PG_CPU_REQUEST - CPU request
#   PG_MEMORY_REQUEST - Memory request
# -----------------------------------------------------------------------------
introspect_postgres() {
    local sts_name="${1:-}"
    local namespace="${2:-${CAMUNDA_NAMESPACE:-camunda}}"

    if [[ -z "$sts_name" ]]; then
        echo -e "${RED}Error: StatefulSet name is required${NC}"
        return 1
    fi

    echo -e "${BLUE}Introspecting PostgreSQL StatefulSet: ${sts_name}${NC}"
    echo "Namespace: ${namespace}"
    echo ""

    # Check if StatefulSet exists
    if ! kubectl get statefulset "${sts_name}" -n "${namespace}" &>/dev/null; then
        echo -e "${RED}Error: StatefulSet ${sts_name} not found in namespace ${namespace}${NC}"
        return 1
    fi

    # Get the full StatefulSet JSON
    local sts_json
    sts_json=$(kubectl get statefulset "${sts_name}" -n "${namespace}" -o json)

    # Extract image from the first container (postgresql container)
    PG_IMAGE=$(echo "$sts_json" | jq -r '.spec.template.spec.containers[0].image')
    export PG_IMAGE
    echo -e "${GREEN}✓ Image:${NC} ${PG_IMAGE}"

    # Extract imagePullSecrets
    local pull_secrets
    pull_secrets=$(echo "$sts_json" | jq -r '.spec.template.spec.imagePullSecrets // [] | .[].name' | tr '\n' ',' | sed 's/,$//')
    PG_IMAGE_PULL_SECRETS="${pull_secrets:-}"
    export PG_IMAGE_PULL_SECRETS
    if [[ -n "$PG_IMAGE_PULL_SECRETS" ]]; then
        echo -e "${GREEN}✓ ImagePullSecrets:${NC} ${PG_IMAGE_PULL_SECRETS}"
    else
        echo -e "${YELLOW}⚠ No ImagePullSecrets found${NC}"
    fi

    # Extract storage class and size from volumeClaimTemplates
    PG_STORAGE_CLASS=$(echo "$sts_json" | jq -r '.spec.volumeClaimTemplates[0].spec.storageClassName // "default"')
    export PG_STORAGE_CLASS
    PG_STORAGE_SIZE=$(echo "$sts_json" | jq -r '.spec.volumeClaimTemplates[0].spec.resources.requests.storage // "8Gi"')
    export PG_STORAGE_SIZE
    echo -e "${GREEN}✓ Storage Class:${NC} ${PG_STORAGE_CLASS}"
    echo -e "${GREEN}✓ Storage Size:${NC} ${PG_STORAGE_SIZE}"

    # Extract replica count
    PG_REPLICAS=$(echo "$sts_json" | jq -r '.spec.replicas // 1')
    export PG_REPLICAS
    echo -e "${GREEN}✓ Replicas:${NC} ${PG_REPLICAS}"

    # Extract resource limits and requests
    local resources
    resources=$(echo "$sts_json" | jq -r '.spec.template.spec.containers[0].resources // {}')

    PG_CPU_LIMIT=$(echo "$resources" | jq -r '.limits.cpu // "1"')
    export PG_CPU_LIMIT
    PG_MEMORY_LIMIT=$(echo "$resources" | jq -r '.limits.memory // "1Gi"')
    export PG_MEMORY_LIMIT
    PG_CPU_REQUEST=$(echo "$resources" | jq -r '.requests.cpu // "250m"')
    export PG_CPU_REQUEST
    PG_MEMORY_REQUEST=$(echo "$resources" | jq -r '.requests.memory // "256Mi"')
    export PG_MEMORY_REQUEST

    echo -e "${GREEN}✓ Resources:${NC}"
    echo "    CPU: ${PG_CPU_REQUEST} / ${PG_CPU_LIMIT}"
    echo "    Memory: ${PG_MEMORY_REQUEST} / ${PG_MEMORY_LIMIT}"

    # Extract PostgreSQL version from image tag
    local pg_version
    pg_version=$(echo "$PG_IMAGE" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "15")
    export PG_VERSION="${pg_version}"
    echo -e "${GREEN}✓ PostgreSQL Version:${NC} ${PG_VERSION}"

    echo ""
    echo -e "${GREEN}Introspection complete!${NC}"

    return 0
}

# -----------------------------------------------------------------------------
# Get PostgreSQL connection info from existing secret
# -----------------------------------------------------------------------------
# Arguments:
#   $1 - Secret name pattern (e.g., camunda-postgresql)
#   $2 - Namespace (optional)
#
# Exports:
#   PG_PASSWORD - PostgreSQL password
#   PG_USERNAME - PostgreSQL username
#   PG_DATABASE - PostgreSQL database name
# -----------------------------------------------------------------------------
get_postgres_credentials() {
    local secret_pattern="${1:-}"
    local namespace="${2:-${CAMUNDA_NAMESPACE:-camunda}}"

    if [[ -z "$secret_pattern" ]]; then
        echo -e "${RED}Error: Secret pattern is required${NC}"
        return 1
    fi

    echo -e "${BLUE}Extracting PostgreSQL credentials...${NC}"

    # Find the secret
    local secret_name
    secret_name=$(kubectl get secrets -n "${namespace}" -o name | grep "${secret_pattern}" | head -1 | sed 's|secret/||')

    if [[ -z "$secret_name" ]]; then
        echo -e "${RED}Error: No secret found matching pattern: ${secret_pattern}${NC}"
        return 1
    fi

    echo "Found secret: ${secret_name}"

    # Extract credentials - try different key names used by Bitnami
    PG_PASSWORD=$(kubectl get secret "${secret_name}" -n "${namespace}" -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d || \
                         kubectl get secret "${secret_name}" -n "${namespace}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || \
                         echo "")
    export PG_PASSWORD

    PG_USERNAME=$(kubectl get secret "${secret_name}" -n "${namespace}" -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || \
                         echo "postgres")
    export PG_USERNAME

    if [[ -n "$PG_PASSWORD" ]]; then
        echo -e "${GREEN}✓ Credentials extracted successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Could not extract password from secret${NC}"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Generate CNPG Cluster manifest from introspected values
# -----------------------------------------------------------------------------
# Arguments:
#   $1 - Cluster name
#   $2 - Database name
#   $3 - Output file (optional, prints to stdout if not provided)
# -----------------------------------------------------------------------------
generate_cnpg_cluster_manifest() {
    local cluster_name="${1:-}"
    local database_name="${2:-}"
    local output_file="${3:-}"
    local namespace="${CAMUNDA_NAMESPACE:-camunda}"

    if [[ -z "$cluster_name" ]] || [[ -z "$database_name" ]]; then
        echo -e "${RED}Error: Cluster name and database name are required${NC}"
        return 1
    fi

    # Ensure introspection was done
    if [[ -z "${PG_IMAGE:-}" ]]; then
        echo -e "${RED}Error: Run introspect_postgres first${NC}"
        return 1
    fi

    local manifest
    manifest=$(cat <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${cluster_name}
  namespace: ${namespace}
spec:
  instances: ${PG_REPLICAS:-1}

  # Use the same image as Bitnami installation
  imageName: ${PG_IMAGE}
  $(if [[ -n "${PG_IMAGE_PULL_SECRETS:-}" ]]; then
    echo "imagePullSecrets:"
    IFS=',' read -ra SECRETS <<< "$PG_IMAGE_PULL_SECRETS"
    for secret in "${SECRETS[@]}"; do
      echo "    - name: ${secret}"
    done
  fi)

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"

  bootstrap:
    initdb:
      database: ${database_name}
      owner: ${PG_USERNAME:-postgres}
      secret:
        name: ${cluster_name}-app-credentials

  storage:
    size: ${PG_STORAGE_SIZE:-8Gi}
    storageClass: ${PG_STORAGE_CLASS:-default}

  resources:
    requests:
      memory: "${PG_MEMORY_REQUEST:-256Mi}"
      cpu: "${PG_CPU_REQUEST:-250m}"
    limits:
      memory: "${PG_MEMORY_LIMIT:-1Gi}"
      cpu: "${PG_CPU_LIMIT:-1}"

  monitoring:
    enablePodMonitor: false
EOF
)

    if [[ -n "$output_file" ]]; then
        echo "$manifest" > "$output_file"
        echo -e "${GREEN}✓ Manifest written to: ${output_file}${NC}"
    else
        echo "$manifest"
    fi

    return 0
}
