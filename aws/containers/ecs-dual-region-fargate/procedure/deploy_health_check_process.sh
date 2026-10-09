#!/bin/bash

###############################################################################
# Deploy the dual-region health-check BPMN process                            #
#                                                                             #
# verify_dual_region.sh and demo-create-instances.sh both start instances of  #
# `dual-region-health-check`. Nothing deployed it, so those checks quietly    #
# did nothing on a fresh cluster. Run this once after the app layer is up.    #
#                                                                             #
# Usage:                                                                      #
#   . ./export_environment_prerequisites.sh                                   #
#   ./deploy_health_check_process.sh [r0|r1|<alb-hostname>]                   #
#                                                                             #
# The deployment is cluster-wide — it does not matter which region receives   #
# it — so the default (region 0) is fine unless that region is down.          #
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
BPMN_FILE="${SCRIPT_DIR}/resources/dual-region-health-check.bpmn"
PROCESS_ID="dual-region-health-check"

: "${ALB_ENDPOINT_0:?ALB_ENDPOINT_0 must be set — source export_environment_prerequisites.sh first}"
: "${ALB_ENDPOINT_1:?ALB_ENDPOINT_1 must be set}"
: "${ADMIN_USER:?ADMIN_USER must be set (default: admin)}"
: "${ADMIN_PASS:?ADMIN_PASS must be set}"

TARGET="${1:-r0}"
case "${TARGET}" in
    r0) HOST="${ALB_ENDPOINT_0}" ;;
    r1) HOST="${ALB_ENDPOINT_1}" ;;
    *)  HOST="${TARGET}" ;;
esac

if [ ! -f "${BPMN_FILE}" ]; then
    echo "ERROR: BPMN file not found at ${BPMN_FILE}" >&2
    exit 1
fi

echo "Deploying ${PROCESS_ID} to http://${HOST} ..."

# Retry: the ALB can return 200 on /v2/topology while a freshly elected leader
# is not yet accepting deployments.
ATTEMPTS=12
for attempt in $(seq 1 "${ATTEMPTS}"); do
    # Bounded: an ALB that accepts the connection but never answers would
    # otherwise block the first attempt forever and the remaining retries would
    # never run — the loop would look like a hang rather than a failure.
    RESPONSE=$(curl -s -w '\n%{http_code}' \
        --connect-timeout 10 --max-time 60 \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X POST "http://${HOST}/v2/deployments" \
        -F "resources=@${BPMN_FILE}" || true)

    CODE=$(echo "${RESPONSE}" | tail -n1)
    BODY=$(echo "${RESPONSE}" | sed '$d')

    if [ "${CODE}" = "200" ] || [ "${CODE}" = "201" ]; then
        KEY=$(echo "${BODY}" | jq -r '.deployments[0].processDefinition.processDefinitionKey // empty')
        echo "Deployed ${PROCESS_ID} (processDefinitionKey=${KEY:-unknown})"
        exit 0
    fi

    echo "  attempt ${attempt}/${ATTEMPTS}: HTTP ${CODE}, retrying in 10s..."
    sleep 10
done

echo "ERROR: could not deploy ${PROCESS_ID} to http://${HOST} after ${ATTEMPTS} attempts" >&2
echo "       last response: ${BODY}" >&2
exit 1
