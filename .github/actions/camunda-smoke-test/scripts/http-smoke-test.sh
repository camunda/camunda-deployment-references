#!/usr/bin/env bash
# =============================================================================
# HTTP Smoke Test for Camunda
#
# Deploys a BPMN process, creates process instances via Zeebe REST API v2,
# waits for propagation, then verifies instances completed.
#
# Supports basic auth, OIDC (client_credentials), and no auth.
# Works for all deployment types (K8s via port-forward, ECS, EC2).
# =============================================================================
set -euo pipefail

log()      { echo "[$(date -u +%H:%M:%S)] $*"; }
pass()     { echo "[$(date -u +%H:%M:%S)] PASS: $*"; }
fail_test(){ echo "[$(date -u +%H:%M:%S)] FAIL: $*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

# ── Configuration from environment ──────────────────────────────────
ZEEBE_URL="${SMOKE_ZEEBE_REST_URL:?SMOKE_ZEEBE_REST_URL is required}"
AUTH_MODE="${SMOKE_AUTH_MODE:-basic}"
BASIC_USER="${SMOKE_BASIC_USER:-demo}"
BASIC_PASSWORD="${SMOKE_BASIC_PASSWORD:-demo}"
TOKEN_URL="${SMOKE_OIDC_TOKEN_URL:-}"
CLIENT_ID="${SMOKE_OIDC_CLIENT_ID:-}"
CLIENT_SECRET="${SMOKE_OIDC_CLIENT_SECRET:-}"
DURATION="${SMOKE_DURATION:-300}"
PI_PER_SECOND="${SMOKE_PI_PER_SECOND:-5}"
MIN_EXPECTED="${SMOKE_MIN_EXPECTED:-10}"
PROPAGATION_WAIT="${SMOKE_PROPAGATION_WAIT:-60}"

PROCESS_ID="smoke-test"

# Strip trailing slash from URL
ZEEBE_URL="${ZEEBE_URL%/}"

# ── Auth setup ──────────────────────────────────────────────────────
AUTH_ARGS=()
LAST_TOKEN_TIME=0
TOKEN_REFRESH_INTERVAL=240

get_oidc_token() {
    # Use --data-urlencode so client_id / client_secret values containing
    # reserved characters (+, &, =, spaces, ...) are encoded correctly.
    curl -sf --connect-timeout 10 --max-time 30 \
        -X POST "$TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=${CLIENT_ID}" \
        --data-urlencode "client_secret=${CLIENT_SECRET}" 2>/dev/null \
        | jq -r '.access_token // empty' 2>/dev/null || echo ""
}

refresh_auth() {
    if [[ "$AUTH_MODE" != "oidc" ]]; then return; fi
    local now
    now=$(date +%s)
    if [[ $((now - LAST_TOKEN_TIME)) -lt $TOKEN_REFRESH_INTERVAL ]]; then
        return
    fi
    local token
    token=$(get_oidc_token)
    if [[ -n "$token" ]]; then
        AUTH_ARGS=(-H "Authorization: Bearer ${token}")
        LAST_TOKEN_TIME=$now
        log "  OIDC token refreshed"
    else
        log "  WARN: Failed to refresh OIDC token"
    fi
}

if [[ "$AUTH_MODE" == "basic" ]]; then
    AUTH_ARGS=(-u "${BASIC_USER}:${BASIC_PASSWORD}")
    log "Auth mode: basic (user=${BASIC_USER})"
elif [[ "$AUTH_MODE" == "oidc" ]]; then
    if [[ -z "$TOKEN_URL" || -z "$CLIENT_ID" ]]; then
        fail_test "OIDC requires TOKEN_URL and CLIENT_ID"
        exit 1
    fi
    OIDC_TOKEN=$(get_oidc_token)
    if [[ -z "$OIDC_TOKEN" ]]; then
        fail_test "Failed to obtain OIDC token from ${TOKEN_URL}"
        exit 1
    fi
    AUTH_ARGS=(-H "Authorization: Bearer ${OIDC_TOKEN}")
    LAST_TOKEN_TIME=$(date +%s)
    log "Auth mode: OIDC (client=${CLIENT_ID})"
else
    log "Auth mode: none"
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
                  id="Definitions_1"
                  targetNamespace="http://bpmn.io/schema/bpmn">
  <bpmn:process id="smoke-test" name="Smoke Test" isExecutable="true">
    <bpmn:startEvent id="start" name="Start">
      <bpmn:outgoing>toEnd</bpmn:outgoing>
    </bpmn:startEvent>
    <bpmn:endEvent id="end" name="End">
      <bpmn:incoming>toEnd</bpmn:incoming>
    </bpmn:endEvent>
    <bpmn:sequenceFlow id="toEnd" sourceRef="start" targetRef="end"/>
  </bpmn:process>
</bpmn:definitions>
BPMN_EOF

# Retry deployment: Zeebe may report ready via /v2/topology before the
# broker fully accepts deployments. Capture HTTP code + body so failures
# are diagnosable instead of silently empty (curl -f swallows the body).
DEPLOY_RESP=""
DEPLOY_CODE="000"
for attempt in $(seq 1 12); do
    DEPLOY_BODY_FILE=$(mktemp /tmp/smoke-deploy-resp-XXXXXX)
    DEPLOY_CODE=$(curl -s -o "$DEPLOY_BODY_FILE" -w "%{http_code}" \
        --connect-timeout 10 --max-time 60 \
        "${AUTH_ARGS[@]}" \
        -X POST "${ZEEBE_URL}/v2/deployments" \
        -H "Accept: application/json" \
        -F "resources=@${BPMN_FILE}" 2>/dev/null || echo "000")
    DEPLOY_RESP=$(cat "$DEPLOY_BODY_FILE")
    rm -f "$DEPLOY_BODY_FILE"
    if [[ "$DEPLOY_CODE" =~ ^2[0-9][0-9]$ ]]; then
        break
    fi
    log "  Deploy attempt ${attempt}/12: HTTP ${DEPLOY_CODE} (retrying in 5s)"
    log "  Response: ${DEPLOY_RESP:0:500}"
    sleep 5
done
rm -f "$BPMN_FILE"

if [[ ! "$DEPLOY_CODE" =~ ^2[0-9][0-9]$ ]]; then
    fail_test "Failed to deploy BPMN process (HTTP ${DEPLOY_CODE}): ${DEPLOY_RESP}"
    exit 1
fi

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
ATTEMPTED=0
SUCCESS_FILE=$(mktemp /tmp/smoke-success-XXXXXX)
trap 'rm -f "$SUCCESS_FILE"' EXIT
START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))
BATCH_SIZE=$((PI_PER_SECOND))
while [[ $(date +%s) -lt $END_TIME ]]; do
    refresh_auth
    BATCH_START=$(date +%s%3N)

    for _ in $(seq 1 "$BATCH_SIZE"); do
        # Append "1" on success only. wait below tolerates per-curl failures
        # (transient 429 / 5xx) so the smoke test stays resilient.
        ( api_call -X POST "${ZEEBE_URL}/v2/process-instances" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "{\"processDefinitionKey\":\"${PROC_DEF_KEY}\"}" \
            -o /dev/null 2>/dev/null \
            && printf '1' >> "$SUCCESS_FILE" ) &
    done
    # Don't abort the whole test on a single transient curl failure; we
    # rely on SUCCESS_FILE to count only the successful POSTs.
    wait || true

    ATTEMPTED=$((ATTEMPTED + BATCH_SIZE))
    CREATED=$(wc -c < "$SUCCESS_FILE" | tr -d '[:space:]')

    # Rate limit: sleep remainder of the second.
    # Convert ms to a fractional seconds string with 3 decimal digits so that
    # e.g. 50ms becomes 0.050s (not 0.50s = 500ms as bare "0.${SLEEP_MS}" would yield).
    BATCH_END=$(date +%s%3N)
    ELAPSED_MS=$((BATCH_END - BATCH_START))
    if [[ $ELAPSED_MS -lt 1000 ]]; then
        SLEEP_MS=$((1000 - ELAPSED_MS))
        SLEEP_SEC=$(printf '0.%03d' "$SLEEP_MS")
        sleep "$SLEEP_SEC"
    fi

    # Log progress every 30s
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [[ $((ELAPSED % 30)) -eq 0 ]] && [[ $ELAPSED -gt 0 ]]; then
        log "  Progress: ${CREATED}/${ATTEMPTED} instances created (${ELAPSED}s elapsed)"
    fi
done

pass "Created ${CREATED}/${ATTEMPTED} process instances in ${DURATION}s"

# ── Wait for propagation ────────────────────────────────────────────
log ""
log "=== Waiting ${PROPAGATION_WAIT}s for search index propagation ==="
# Keep the kubectl port-forwards alive during the propagation wait.
# A bare `sleep 60` lets the SPDY/TCP idle timer (typically 4 min on
# managed cloud LBs, but as low as 60s on AKS LB / Azure ILB / some
# CNIs) close both port-forward streams. When they die, every
# subsequent verify call returns HTTP 000000 even though Zeebe and
# Keycloak are healthy. Probing /v2/topology and the OIDC token
# endpoint every 10s keeps both PFs warm.
KEEPALIVE_INTERVAL=10
KA_END=$(($(date +%s) + PROPAGATION_WAIT))
while [[ $(date +%s) -lt $KA_END ]]; do
    # Zeebe REST: cheapest healthcheck. Ignore failures — the verify
    # loop below will diagnose any persistent unreachability.
    curl -s -o /dev/null --connect-timeout 5 --max-time 10 \
        "${AUTH_ARGS[@]}" "${ZEEBE_URL}/v2/topology" 2>/dev/null || true
    # Keycloak: hit the token endpoint to keep its PF warm. We discard
    # the response; refresh_auth will obtain fresh credentials before
    # the verify loop.
    if [[ "$AUTH_MODE" == "oidc" && -n "$TOKEN_URL" ]]; then
        curl -s -o /dev/null --connect-timeout 5 --max-time 10 \
            -X POST "$TOKEN_URL" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "grant_type=client_credentials" \
            --data-urlencode "client_id=${CLIENT_ID}" \
            --data-urlencode "client_secret=${CLIENT_SECRET}" \
            2>/dev/null || true
    fi
    sleep "$KEEPALIVE_INTERVAL"
done

# ── Verify process instances ────────────────────────────────────────
log ""
log "=== Verifying process instances ==="

# Helper: search the secondary storage with explicit HTTP code + body
# capture so failures are diagnosable instead of being silently swallowed
# by `curl -sf` (which returns empty body on HTTP 4xx/5xx). Stores the
# response in $SEARCH_RESP and the HTTP status in $SEARCH_CODE.
search_process_instances() {
    local body="$1"
    local resp_file
    resp_file=$(mktemp /tmp/smoke-search-resp-XXXXXX)
    SEARCH_CODE=$(curl -s -o "$resp_file" -w "%{http_code}" \
        --connect-timeout 10 --max-time 30 \
        "${AUTH_ARGS[@]}" \
        -X POST "${ZEEBE_URL}/v2/process-instances/search" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$body" 2>/dev/null || echo "000")
    SEARCH_RESP=$(cat "$resp_file")
    rm -f "$resp_file"
}

# Refresh OIDC tokens between create-loop and search loop AND on every
# attempt: ES indexing of 1485 PIs may push the search past the token
# expiry, leading to silent 401s.
FOUND=0
SEARCH_RESP=""
SEARCH_CODE="000"
# Bumped from 18 to 30 attempts (5 min) to tolerate slower-than-usual ES
# indexing on cold ROSA HCP clusters. Combined with the 60s propagation
# wait above, total tolerance is ~6 min.
SEARCH_MAX_ATTEMPTS=30
for attempt in $(seq 1 "$SEARCH_MAX_ATTEMPTS"); do
    refresh_auth
    search_process_instances \
        "{\"filter\":{\"processDefinitionId\":\"${PROCESS_ID}\"}}"

    if [[ "$SEARCH_CODE" =~ ^2[0-9][0-9]$ ]]; then
        FOUND=$(echo "$SEARCH_RESP" \
            | jq -r '.page.totalItems // .totalItems // 0' 2>/dev/null \
            || echo "0")
    else
        FOUND=0
    fi

    if [[ "$FOUND" -ge "$MIN_EXPECTED" ]]; then
        break
    fi
    log "  Attempt ${attempt}/${SEARCH_MAX_ATTEMPTS}: HTTP ${SEARCH_CODE}, found ${FOUND} (need >= ${MIN_EXPECTED}), waiting 10s..."
    # If the search returned HTTP 000000 (connection refused / port-forward
    # dead), warn loudly so it is obvious in the logs that the issue is
    # client-side, not Camunda-side. The actual port-forward is owned by
    # the action.yml step; we cannot restart it from here, but the
    # /v2/topology probe below keeps the SPDY stream warm and may let
    # kubectl reopen the underlying connection on next attempt.
    if [[ "$SEARCH_CODE" == "000" ]]; then
        log "  WARN: Got HTTP 000 — likely a dropped kubectl port-forward, not a Camunda issue."
    fi
    # Split the 10s wait into 2x 5s with a topology ping in the middle so
    # the Zeebe port-forward never sits idle long enough to be reaped.
    sleep 5
    curl -s -o /dev/null --connect-timeout 5 --max-time 10 \
        "${AUTH_ARGS[@]}" "${ZEEBE_URL}/v2/topology" 2>/dev/null || true
    sleep 5
done

if [[ "$FOUND" -ge "$MIN_EXPECTED" ]]; then
    pass "Found ${FOUND} process instances (expected >= ${MIN_EXPECTED})"
else
    fail_test "Found ${FOUND} process instances (expected >= ${MIN_EXPECTED})"
    log "  Last search HTTP code: ${SEARCH_CODE}"
    log "  Last search response : ${SEARCH_RESP:0:1000}"

    # Probe with an empty filter to disambiguate "ES indexer is broken"
    # from "filter does not match anything". This is purely diagnostic.
    refresh_auth
    search_process_instances "{}"
    PROBE_TOTAL=$(echo "$SEARCH_RESP" \
        | jq -r '.page.totalItems // .totalItems // 0' 2>/dev/null \
        || echo "0")
    log "  Diagnostic probe (empty filter): HTTP ${SEARCH_CODE}, totalItems=${PROBE_TOTAL}"
    log "  Probe response: ${SEARCH_RESP:0:500}"
fi

# ── Check for completed instances ───────────────────────────────────
log ""
log "=== Checking for completed instances ==="

refresh_auth
search_process_instances \
    "{\"filter\":{\"processDefinitionId\":\"${PROCESS_ID}\",\"state\":\"COMPLETED\"}}"

if [[ "$SEARCH_CODE" =~ ^2[0-9][0-9]$ ]]; then
    COMPLETED=$(echo "$SEARCH_RESP" \
        | jq -r '.page.totalItems // .totalItems // 0' 2>/dev/null \
        || echo "0")
else
    COMPLETED=0
fi

if [[ "$COMPLETED" -gt 0 ]]; then
    pass "${COMPLETED} instances completed end-to-end"
else
    fail_test "No completed instances found"
    log "  Last search HTTP code: ${SEARCH_CODE}"
    log "  Last search response : ${SEARCH_RESP:0:1000}"
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
