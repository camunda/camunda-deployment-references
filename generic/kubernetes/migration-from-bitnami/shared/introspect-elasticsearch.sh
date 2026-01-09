#!/bin/bash
# =============================================================================
# Shared Elasticsearch Introspection Script
# =============================================================================
# This script introspects a Bitnami Elasticsearch StatefulSet to extract:
# - Full image path (including private registry)
# - ImagePullSecrets
# - Storage class and size
# - Resource limits
# - Replica count
# - JVM settings
#
# Usage: source this script and call introspect_elasticsearch <statefulset-name>
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Introspect Elasticsearch StatefulSet
# -----------------------------------------------------------------------------
# Arguments:
#   $1 - StatefulSet name (or pattern to search)
#   $2 - Namespace (optional, defaults to CAMUNDA_NAMESPACE)
#
# Exports:
#   ES_IMAGE - Full image path
#   ES_IMAGE_PULL_SECRETS - Comma-separated list of pull secrets
#   ES_STORAGE_CLASS - Storage class name
#   ES_STORAGE_SIZE - Storage size (e.g., 30Gi)
#   ES_REPLICAS - Number of replicas
#   ES_CPU_LIMIT - CPU limit
#   ES_MEMORY_LIMIT - Memory limit
#   ES_CPU_REQUEST - CPU request
#   ES_MEMORY_REQUEST - Memory request
#   ES_JAVA_OPTS - JVM options
#   ES_VERSION - Elasticsearch version
# -----------------------------------------------------------------------------
introspect_elasticsearch() {
    local _sts_pattern="${1:-elasticsearch}"
    local namespace="${2:-${CAMUNDA_NAMESPACE:-camunda}}"

    echo -e "${BLUE}Introspecting Elasticsearch in namespace: ${namespace}${NC}"
    echo ""

    # Find the StatefulSet - try different patterns
    local sts_name
    sts_name=$(kubectl get statefulset -n "${namespace}" -o name 2>/dev/null | grep -E "(elasticsearch|es)" | head -1 | sed 's|statefulset.apps/||' || echo "")

    if [[ -z "$sts_name" ]]; then
        # Try to find by label
        sts_name=$(kubectl get statefulset -n "${namespace}" -l "app.kubernetes.io/component=elasticsearch" -o name 2>/dev/null | head -1 | sed 's|statefulset.apps/||' || echo "")
    fi

    if [[ -z "$sts_name" ]]; then
        echo -e "${RED}Error: No Elasticsearch StatefulSet found in namespace ${namespace}${NC}"
        echo "Tried patterns: elasticsearch, es, label app.kubernetes.io/component=elasticsearch"
        return 1
    fi

    echo -e "${GREEN}Found StatefulSet:${NC} ${sts_name}"

    # Get the full StatefulSet JSON
    local sts_json
    sts_json=$(kubectl get statefulset "${sts_name}" -n "${namespace}" -o json)

    # Extract image from the elasticsearch container
    ES_IMAGE=$(echo "$sts_json" | jq -r '.spec.template.spec.containers[] | select(.name | test("elasticsearch|es")) | .image' | head -1)
    export ES_IMAGE
    if [[ -z "$ES_IMAGE" ]] || [[ "$ES_IMAGE" == "null" ]]; then
        # Fallback to first container
        ES_IMAGE=$(echo "$sts_json" | jq -r '.spec.template.spec.containers[0].image')
        export ES_IMAGE
    fi
    echo -e "${GREEN}✓ Image:${NC} ${ES_IMAGE}"

    # Extract imagePullSecrets
    local pull_secrets
    pull_secrets=$(echo "$sts_json" | jq -r '.spec.template.spec.imagePullSecrets // [] | .[].name' | tr '\n' ',' | sed 's/,$//')
    ES_IMAGE_PULL_SECRETS="${pull_secrets:-}"
    export ES_IMAGE_PULL_SECRETS
    if [[ -n "$ES_IMAGE_PULL_SECRETS" ]]; then
        echo -e "${GREEN}✓ ImagePullSecrets:${NC} ${ES_IMAGE_PULL_SECRETS}"
    else
        echo -e "${YELLOW}⚠ No ImagePullSecrets found${NC}"
    fi

    # Extract storage class and size from volumeClaimTemplates
    ES_STORAGE_CLASS=$(echo "$sts_json" | jq -r '.spec.volumeClaimTemplates[0].spec.storageClassName // "default"')
    export ES_STORAGE_CLASS
    ES_STORAGE_SIZE=$(echo "$sts_json" | jq -r '.spec.volumeClaimTemplates[0].spec.resources.requests.storage // "30Gi"')
    export ES_STORAGE_SIZE
    echo -e "${GREEN}✓ Storage Class:${NC} ${ES_STORAGE_CLASS}"
    echo -e "${GREEN}✓ Storage Size:${NC} ${ES_STORAGE_SIZE}"

    # Extract replica count
    ES_REPLICAS=$(echo "$sts_json" | jq -r '.spec.replicas // 1')
    export ES_REPLICAS
    echo -e "${GREEN}✓ Replicas:${NC} ${ES_REPLICAS}"

    # Extract resource limits and requests from elasticsearch container
    local container_json
    container_json=$(echo "$sts_json" | jq -r '.spec.template.spec.containers[] | select(.name | test("elasticsearch|es"))' | head -1)
    if [[ -z "$container_json" ]] || [[ "$container_json" == "null" ]]; then
        container_json=$(echo "$sts_json" | jq -r '.spec.template.spec.containers[0]')
    fi

    local resources
    resources=$(echo "$container_json" | jq -r '.resources // {}')

    ES_CPU_LIMIT=$(echo "$resources" | jq -r '.limits.cpu // "2"')
    export ES_CPU_LIMIT
    ES_MEMORY_LIMIT=$(echo "$resources" | jq -r '.limits.memory // "4Gi"')
    export ES_MEMORY_LIMIT
    ES_CPU_REQUEST=$(echo "$resources" | jq -r '.requests.cpu // "500m"')
    export ES_CPU_REQUEST
    ES_MEMORY_REQUEST=$(echo "$resources" | jq -r '.requests.memory // "2Gi"')
    export ES_MEMORY_REQUEST

    echo -e "${GREEN}✓ Resources:${NC}"
    echo "    CPU: ${ES_CPU_REQUEST} / ${ES_CPU_LIMIT}"
    echo "    Memory: ${ES_MEMORY_REQUEST} / ${ES_MEMORY_LIMIT}"

    # Extract JAVA_OPTS / ES_JAVA_OPTS from environment variables
    ES_JAVA_OPTS=$(echo "$container_json" | jq -r '.env[] | select(.name | test("JAVA_OPTS|ES_JAVA_OPTS")) | .value' 2>/dev/null | head -1 || echo "-Xms1g -Xmx1g")
    export ES_JAVA_OPTS
    echo -e "${GREEN}✓ Java Opts:${NC} ${ES_JAVA_OPTS}"

    # Extract Elasticsearch version from image tag
    local es_version
    es_version=$(echo "$ES_IMAGE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "8.15.0")
    export ES_VERSION="${es_version}"
    echo -e "${GREEN}✓ Elasticsearch Version:${NC} ${ES_VERSION}"

    # Store the StatefulSet name for later use
    export ES_STS_NAME="${sts_name}"

    echo ""
    echo -e "${GREEN}Introspection complete!${NC}"

    return 0
}

# -----------------------------------------------------------------------------
# Get Elasticsearch credentials from existing secret
# -----------------------------------------------------------------------------
# Arguments:
#   $1 - Secret name pattern (e.g., elasticsearch)
#   $2 - Namespace (optional)
#
# Exports:
#   ES_PASSWORD - Elasticsearch password
#   ES_USERNAME - Elasticsearch username (usually 'elastic')
# -----------------------------------------------------------------------------
get_elasticsearch_credentials() {
    local secret_pattern="${1:-elasticsearch}"
    local namespace="${2:-${CAMUNDA_NAMESPACE:-camunda}}"

    echo -e "${BLUE}Extracting Elasticsearch credentials...${NC}"

    # Find the secret - try different patterns
    local secret_name
    secret_name=$(kubectl get secrets -n "${namespace}" -o name | grep -E "${secret_pattern}" | head -1 | sed 's|secret/||')

    if [[ -z "$secret_name" ]]; then
        echo -e "${YELLOW}⚠ No secret found matching pattern: ${secret_pattern}${NC}"
        export ES_PASSWORD=""
        export ES_USERNAME="elastic"
        return 0
    fi

    echo "Found secret: ${secret_name}"

    # Extract credentials - try different key names
    ES_PASSWORD=$(kubectl get secret "${secret_name}" -n "${namespace}" -o jsonpath='{.data.elasticsearch-password}' 2>/dev/null | base64 -d || \
                         kubectl get secret "${secret_name}" -n "${namespace}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || \
                         kubectl get secret "${secret_name}" -n "${namespace}" -o jsonpath='{.data.elastic}' 2>/dev/null | base64 -d || \
                         echo "")
    export ES_PASSWORD

    export ES_USERNAME="elastic"

    if [[ -n "$ES_PASSWORD" ]]; then
        echo -e "${GREEN}✓ Credentials extracted successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Could not extract password from secret${NC}"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Generate ECK Elasticsearch manifest from introspected values
# -----------------------------------------------------------------------------
# Arguments:
#   $1 - Cluster name
#   $2 - Output file (optional, prints to stdout if not provided)
# -----------------------------------------------------------------------------
generate_eck_cluster_manifest() {
    local cluster_name="${1:-camunda-elasticsearch}"
    local output_file="${2:-}"
    local namespace="${CAMUNDA_NAMESPACE:-camunda}"

    # Ensure introspection was done
    if [[ -z "${ES_IMAGE:-}" ]]; then
        echo -e "${RED}Error: Run introspect_elasticsearch first${NC}"
        return 1
    fi

    # Calculate heap size from memory limit (50% of memory)
    local memory_gb
    memory_gb=$(echo "${ES_MEMORY_LIMIT}" | grep -oE '[0-9]+' | head -1)
    local heap_size="${memory_gb:-2}g"
    # Cap at half of memory
    heap_size="$((memory_gb / 2))g"

    local manifest
    manifest=$(cat <<EOF
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: ${cluster_name}
  namespace: ${namespace}
spec:
  version: ${ES_VERSION}

  # Use the same image as Bitnami installation
  image: ${ES_IMAGE}
  $(if [[ -n "${ES_IMAGE_PULL_SECRETS:-}" ]]; then
    echo "imagePullSecrets:"
    IFS=',' read -ra SECRETS <<< "$ES_IMAGE_PULL_SECRETS"
    for secret in "${SECRETS[@]}"; do
      echo "    - name: ${secret}"
    done
  fi)

  nodeSets:
    - name: default
      count: ${ES_REPLICAS:-1}
      config:
        node.store.allow_mmap: false
      podTemplate:
        spec:
          containers:
            - name: elasticsearch
              resources:
                requests:
                  memory: "${ES_MEMORY_REQUEST:-2Gi}"
                  cpu: "${ES_CPU_REQUEST:-500m}"
                limits:
                  memory: "${ES_MEMORY_LIMIT:-4Gi}"
                  cpu: "${ES_CPU_LIMIT:-2}"
              env:
                - name: ES_JAVA_OPTS
                  value: "-Xms${heap_size} -Xmx${heap_size}"
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: ${ES_STORAGE_SIZE:-30Gi}
            storageClassName: ${ES_STORAGE_CLASS:-default}

  http:
    tls:
      selfSignedCertificate:
        disabled: true
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
