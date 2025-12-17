#!/bin/bash
# =============================================================================
# Orchestration Migration - Step 6: Validate and Show Cleanup Commands
# =============================================================================
# This script validates the migration and shows commands to clean up
# Bitnami resources (as echo only - user decides when to run them).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATION_STATE_DIR="${SCRIPT_DIR}/.state"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  Orchestration Migration - Step 6: Validate and Cleanup"
echo "============================================================================="
echo ""

# Load state
if [[ ! -f "${MIGRATION_STATE_DIR}/elasticsearch.env" ]]; then
    echo -e "${RED}Error: State not found. Run previous steps first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${MIGRATION_STATE_DIR}/elasticsearch.env"

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
ECK_HOST="${ECK_SERVICE}.${NAMESPACE}.svc.cluster.local"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

# =============================================================================
# Validation
# =============================================================================

echo -e "${BLUE}=== Validating ECK Cluster ===${NC}"
echo ""

# Check ECK cluster health
ECK_HEALTH=$(kubectl run es-health-check \
    --image="${ES_IMAGE}" \
    --restart=Never \
    --rm -i \
    --namespace="${NAMESPACE}" \
    -- curl -s -u "elastic:${ECK_PASSWORD}" "http://${ECK_HOST}:9200/_cluster/health" 2>/dev/null || echo "{}")

HEALTH_STATUS=$(echo "${ECK_HEALTH}" | jq -r '.status // "unknown"')

if [[ "${HEALTH_STATUS}" == "green" ]] || [[ "${HEALTH_STATUS}" == "yellow" ]]; then
    echo -e "${GREEN}✓ ECK cluster health: ${HEALTH_STATUS}${NC}"
else
    echo -e "${RED}✗ ECK cluster health: ${HEALTH_STATUS}${NC}"
fi

echo ""
echo -e "${BLUE}=== Validating Camunda Components ===${NC}"
echo ""

# Note: Zeebe exporting was soft-paused in step 3, but since Zeebe was restarted
# with new configuration in step 5, exporting automatically resumes.
# If components were not restarted (edge case), manually resume with:
#   curl -X POST "http://<zeebe-gateway>:9600/actuator/exporting/resume"

COMPONENTS=("zeebe" "zeebe-gateway" "operate" "tasklist" "optimize")
ALL_HEALTHY=true

for comp in "${COMPONENTS[@]}"; do
    DEPLOYMENT="${RELEASE_NAME}-${comp}"

    # Check if running
    READY=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || \
            kubectl get statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || \
            echo "0")

    DESIRED=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || \
              kubectl get statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || \
              echo "0")

    if [[ "${READY}" == "${DESIRED}" ]] && [[ "${READY}" != "0" ]]; then
        echo -e "${GREEN}✓ ${comp}: ${READY}/${DESIRED} ready${NC}"
    else
        echo -e "${RED}✗ ${comp}: ${READY}/${DESIRED} ready${NC}"
        ALL_HEALTHY=false
    fi
done

echo ""
echo -e "${BLUE}=== Validating Data ===${NC}"
echo ""

# Check document counts
kubectl run es-doc-count \
    --image="${ES_IMAGE}" \
    --restart=Never \
    --rm -i \
    --namespace="${NAMESPACE}" \
    -- /bin/bash -c "
        echo 'Index document counts:'
        curl -s -u 'elastic:${ECK_PASSWORD}' 'http://${ECK_HOST}:9200/_cat/indices?v&s=index' 2>/dev/null | head -20
        echo ''
        echo '(showing first 20 indices)'
    " 2>/dev/null || echo "Could not retrieve index counts"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================================================="
if [[ "${ALL_HEALTHY}" == "true" ]]; then
    echo -e "${GREEN}  Migration Validated Successfully!${NC}"
else
    echo -e "${YELLOW}  Migration Complete with Warnings${NC}"
fi
echo "============================================================================="
echo ""

# =============================================================================
# Cleanup Commands (Echo Only)
# =============================================================================

echo -e "${BLUE}=== Bitnami Cleanup Commands ===${NC}"
echo ""
echo -e "${YELLOW}The following commands will remove Bitnami Elasticsearch resources.${NC}"
echo -e "${YELLOW}Run these ONLY after you have verified the migration is successful${NC}"
echo -e "${YELLOW}and you are confident you no longer need the Bitnami installation.${NC}"
echo ""
echo "# Wait 24-48 hours before running these commands"
echo ""
echo "# ============================================================================="
echo "# DELETE BITNAMI ELASTICSEARCH DATA - THIS IS IRREVERSIBLE!"
echo "# ============================================================================="
echo ""

# StatefulSet
echo "# Delete Bitnami Elasticsearch StatefulSet"
echo "echo \"Deleting StatefulSet ${ES_STS_NAME}...\""
echo "kubectl delete statefulset ${ES_STS_NAME} -n ${NAMESPACE} --cascade=orphan"
echo ""

# Pods (if any orphaned)
echo "# Delete any orphaned Elasticsearch pods"
echo "echo \"Deleting orphaned pods...\""
echo "kubectl delete pods -l app.kubernetes.io/component=elasticsearch -n ${NAMESPACE}"
echo ""

# Services
echo "# Delete Bitnami Elasticsearch services"
ES_SVC_BASE="${ES_STS_NAME/-master/}"
echo "echo \"Deleting services...\""
echo "kubectl delete service ${ES_SVC_BASE} -n ${NAMESPACE} --ignore-not-found"
echo "kubectl delete service ${ES_SVC_BASE}-headless -n ${NAMESPACE} --ignore-not-found"
echo ""

# PVCs - THE MOST DANGEROUS PART
echo "# Delete Bitnami Elasticsearch PVCs (DATA LOSS!)"
echo "echo \"WARNING: This will delete all Bitnami Elasticsearch data!\""
echo "echo \"Press Ctrl+C within 10 seconds to cancel...\""
echo "sleep 10"
echo "kubectl delete pvc -l app.kubernetes.io/component=elasticsearch -n ${NAMESPACE}"
echo ""

# Secrets
echo "# Delete Bitnami Elasticsearch secrets"
echo "echo \"Deleting secrets...\""
echo "kubectl delete secret ${RELEASE_NAME}-elasticsearch -n ${NAMESPACE} --ignore-not-found"
echo ""

# ConfigMaps
echo "# Delete Bitnami Elasticsearch configmaps"
echo "echo \"Deleting configmaps...\""
echo "kubectl delete configmap -l app.kubernetes.io/component=elasticsearch -n ${NAMESPACE}"
echo ""

echo "# ============================================================================="
echo "# CLEANUP MIGRATION RESOURCES"
echo "# ============================================================================="
echo ""

echo "# Delete backup jobs"
echo "kubectl delete jobs -l app=es-migration -n ${NAMESPACE}"
echo ""

echo "# Delete backup PVC (optional - may want to keep for safety)"
echo "# kubectl delete pvc ${BACKUP_PVC_NAME:-migration-backup} -n ${NAMESPACE}"
echo ""

echo "# Clean up state directory"
echo "# rm -rf ${MIGRATION_STATE_DIR}"
echo ""

echo "============================================================================="
echo ""
echo -e "${GREEN}Migration complete!${NC}"
echo ""
echo "The ECK-managed Elasticsearch cluster is now serving Camunda."
echo "Bitnami Elasticsearch is still running but no longer in use."
echo ""
echo "Next steps:"
echo "  1. Monitor the application for 24-48 hours"
echo "  2. Verify all data is accessible and correct"
echo "  3. Run the cleanup commands above when ready"
echo ""
