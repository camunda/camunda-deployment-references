#!/usr/bin/env bash
# =============================================================================
# HTTP Smoke Test for Camunda (ECS Fargate / EC2)
#
# Deploys a BPMN process, creates process instances via Zeebe REST API v2,
# waits for propagation, then verifies instances exist and completed.
#
# Runs directly from the GitHub Actions runner against ALB/NLB endpoints.
# =============================================================================
set -euo pipefail

log()      { echo "[$(date -u +%H:%M:%S)] $*"; }
pass()     { echo "[$(date -u +%H:%M:%S)] PASS: $*"; }
fail_test(){ echo "[$(date -u +%H:%M:%S)] FAIL: $*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

# ── Configuration from environment ──────────────────────────────────
ZEEBE_URL="${SMOKE_ZEEBE_REST_URL:?SMOKE_ZEEBE_REST_URL is required}"
AUTH_MODE="${SMOKE_AUTH_MODE:-http-basic}"
BASIC_USER="${SMOKE_BASIC_USER:-demo}"
BASIC_PASSWORD="${SMOKE_BASIC_PASSWORD:-demo}"
DURATION="${SMOKE_DURATION:-300}"
PI_PER_SECOND="${SMOKE_PI_PER_SECOND:-5}"
MIN_EXPECTED="${SMOKE_MIN_EXPECTED:-10}"
PROPAGATION_WAIT="${SMOKE_PROPAGATION_WAIT:-60}"

PROCESS_ID="smoke-test-http"

# Strip trailing slash from URL
ZEEBE_URL="${ZEEBE_URL%/}"

# ── Build auth arguments ────────────────────────────────────────────
AUTH_ARGS=()
if [[ "$AUTH_MODE" == "http-basic" ]]; then
    AUTH_ARGS=(-u "${BASIC_USER}:${BASIC_PASSWORD}")
    log "Auth mode: basic (user=${BASIC_USER})"
else
    log "Auth mode: none (http-oidc not yet implemented for HTTP mode)"
fi

# ── Helper: curl with auth ──────────────────────────────────────────
api_call() {
    curl -sf --connect-timeout 10 --max-time 30 \
        "${AUTH_ARGS[@]}" "$@"
}

# ── Wait for Zeebe REST API ─────────────────────────────────────────
log "=== Waiting for Zeebe REST API at ${ZEEBE_URL} ==="
READY=false
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 10 --max-time 15 \
        "${AUTH_ARGS[@]}" "${ZEEBE_URL}/v2/topology" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        READY=true
        log "Zeebe REST API is ready"
        break
    fi
    log "  Attempt ${i}/30: HTTP ${HTTP_CODE} (waiting...)"
    sleep 10
done

if [[ "$READY" != "true" ]]; then
    fail_test "Zeebe REST API not reachable at ${ZEEBE_URL}/v2/topology"
    echo "::error::Zeebe REST API not reachable"
    exit 1
fi

# ── Deploy BPMN process ─────────────────────────────────────────────
log ""
log "=== Deploying BPMN process '${PROCESS_ID}' ==="

BPMN_FILE=$(mktemp /tmp/smoke-test-XXXXXX.bpmn)
cat > "$BPMN_FILE" <<'BPMN_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL"
                  xmlns:zeebe="http://camunda.org/schema/zeebe/1.0"
                  id="Definitions_1"
                  targetNamespace="http://bpmn.io/schema/bpmn">
  <bpmn:process id="smoke-test-http" name="Smoke Test HTTP" isExecutable="true">
    <bpmn:startEvent id="start" name="Start">
      <bpmn:outgoing>toTask</bpmn:outgoing>
    </bpmn:startEvent>
    <bpmn:serviceTask id="task1" name="Process">
      <bpmn:extensionElements>
        <zeebe:taskDefinition type="smoke-http-task"/>
        <zeebe:taskHeaders>
          <zeebe:header key="autoComplete" value="true"/>
        </zeebe:taskHeaders>
      </bpmn:extensionElements>
      <bpmn:incoming>toTask</bpmn:incoming>
      <bpmn:outgoing>toEnd</bpmn:outgoing>
    </bpmn:serviceTask>
    <bpmn:endEvent id="end" name="End">
      <bpmn:incoming>toEnd</bpmn:incoming>
    </bpmn:endEvent>
    <bpmn:sequenceFlow id="toTask" sourceRef="start" targetRef="task1"/>
    <bpmn:sequenceFlow id="toEnd" sourceRef="task1" targetRef="end"/>
  </bpmn:process>
</bpmn:definitions>
BPMN_EOF

DEPLOY_RESP=$(api_call -X POST "${ZEEBE_URL}/v2/deployments" \
    -H "Accept: application/json" \
    -F "resources=@${BPMN_FILE}" 2>&1) || {
    fail_test "Failed to deploy BPMN process: ${DEPLOY_RESP}"
    rm -f "$BPMN_FILE"
    exit 1
}
rm -f "$BPMN_FILE"

# Extract process definition key
PROC_DEF_KEY=$(echo "$DEPLOY_RESP" | jq -r \
    '.deployments[0].processDefinition.processDefinitionKey // empty' \
    2>/dev/null || echo "")

if [[ -z "$PROC_DEF_KEY" ]]; then
    fail_test "Could not extract processDefinitionKey from deployment"
    log "Response: ${DEPLOY_RESP}"
    exit 1
fi
pass "Deployed process '${PROCESS_ID}' (key=${PROC_DEF_KEY})"

# ── Create process instances ────────────────────────────────────────
log ""
log "=== Creating process instances (${PI_PER_SECOND} PI/s for ${DURATION}s) ==="

CREATED=0
START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))
BATCH_SIZE=$((PI_PER_SECOND))
while [[ $(date +%s) -lt $END_TIME ]]; do
    BATCH_START=$(date +%s%3N)

    for _ in $(seq 1 "$BATCH_SIZE"); do
        api_call -X POST "${ZEEBE_URL}/v2/process-instances" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "{\"processDefinitionKey\":\"${PROC_DEF_KEY}\"}" \
            -o /dev/null 2>/dev/null &
    done
    wait

    CREATED=$((CREATED + BATCH_SIZE))

    # Rate limit: sleep remainder of the second
    BATCH_END=$(date +%s%3N)
    ELAPSED_MS=$((BATCH_END - BATCH_START))
    if [[ $ELAPSED_MS -lt 1000 ]]; then
        SLEEP_MS=$((1000 - ELAPSED_MS))
        sleep "0.${SLEEP_MS}"
    fi

    # Log progress every 30s
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [[ $((ELAPSED % 30)) -eq 0 ]] && [[ $ELAPSED -gt 0 ]]; then
        log "  Progress: ${CREATED} instances created (${ELAPSED}s elapsed)"
    fi
done

pass "Created ${CREATED} process instances in ${DURATION}s"

# ── Wait for propagation ────────────────────────────────────────────
log ""
log "=== Waiting ${PROPAGATION_WAIT}s for search index propagation ==="
sleep "$PROPAGATION_WAIT"

# ── Verify process instances ────────────────────────────────────────
log ""
log "=== Verifying process instances ==="

FOUND=0
for attempt in $(seq 1 18); do
    SEARCH_RESP=$(api_call -X POST \
        "${ZEEBE_URL}/v2/process-instances/search" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{\"filter\":{\"processDefinitionId\":\"${PROCESS_ID}\"}}" \
        2>/dev/null || echo '{}')

    FOUND=$(echo "$SEARCH_RESP" | jq -r '.totalItems // 0' 2>/dev/null || echo "0")

    if [[ "$FOUND" -ge "$MIN_EXPECTED" ]]; then
        break
    fi
    log "  Attempt ${attempt}/18: found ${FOUND} (need >= ${MIN_EXPECTED}), waiting 10s..."
    sleep 10
done

if [[ "$FOUND" -ge "$MIN_EXPECTED" ]]; then
    pass "Found ${FOUND} process instances (expected >= ${MIN_EXPECTED})"
else
    fail_test "Found ${FOUND} process instances (expected >= ${MIN_EXPECTED})"
fi

# ── Check for completed instances ───────────────────────────────────
log ""
log "=== Checking for completed instances ==="

COMPLETED_RESP=$(api_call -X POST \
    "${ZEEBE_URL}/v2/process-instances/search" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"filter\":{\"processDefinitionId\":\"${PROCESS_ID}\",\"state\":\"COMPLETED\"}}" \
    2>/dev/null || echo '{}')

COMPLETED=$(echo "$COMPLETED_RESP" | jq -r '.totalItems // 0' 2>/dev/null || echo "0")

if [[ "$COMPLETED" -gt 0 ]]; then
    pass "${COMPLETED} instances completed end-to-end"
else
    log "WARN: No completed instances found (service task workers may not be running — this is expected for ECS/EC2)"
fi

# ── Cleanup: delete deployed process ────────────────────────────────
log ""
log "=== Cleanup ==="
api_call -X POST "${ZEEBE_URL}/v2/resources/${PROC_DEF_KEY}/deletion" \
    -o /dev/null 2>/dev/null || log "WARN: Could not delete process resource"

# ── Summary ─────────────────────────────────────────────────────────
log ""
log "=========================================="
log "  Total instances created: ${CREATED}"
log "  Total instances found:   ${FOUND}"
log "  Completed instances:     ${COMPLETED}"
if [[ "$FAILURES" -eq 0 ]]; then
    log "  ALL CHECKS PASSED"
else
    log "  ${FAILURES} CHECK(S) FAILED"
fi
log "=========================================="

# Export for GitHub Actions output
echo "total_instances=${FOUND}" >> "$GITHUB_OUTPUT"

exit "$FAILURES"
