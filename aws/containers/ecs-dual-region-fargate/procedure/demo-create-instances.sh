#!/bin/bash
# Demo script: Creates Camunda process instances every 2 seconds against the
# dual-region ECS deployment.
#
# Usage:
#   ./demo-create-instances.sh [r0|r1|<alb-hostname>] [process-id]
#
# Examples:
#   ./demo-create-instances.sh                       # region 0 ALB (default)
#   ./demo-create-instances.sh r1                    # region 1 ALB
#   ./demo-create-instances.sh r0 bigVarProcess
#   ./demo-create-instances.sh ecs-dr-foo-r0-alb.us-east-1.elb.amazonaws.com
#
# Credentials:
#   The script reads ADMIN_USER (default: admin) and ADMIN_PASS from the
#   environment. If ADMIN_PASS is not set, it falls back to
#   `terraform output -raw admin_user_password` run from ../terraform/app/.
#
#   ADMIN_PASS=mysecret ./demo-create-instances.sh r0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_APP_DIR="${SCRIPT_DIR}/../terraform/app"

TARGET="${1:-r0}"
PROCESS_ID="${2:-bigVarProcess}"
ADMIN_USER="${ADMIN_USER:-admin}"

# Resolve the target into an ALB hostname.
case "$TARGET" in
    r0)
        HOST=$(terraform -chdir="$TF_APP_DIR" output -raw region_0_alb_endpoint)
        ;;
    r1)
        HOST=$(terraform -chdir="$TF_APP_DIR" output -raw region_1_alb_endpoint)
        ;;
    *)
        HOST="$TARGET"
        ;;
esac

# Resolve the admin password.
if [ -z "${ADMIN_PASS:-}" ]; then
    ADMIN_PASS=$(terraform -chdir="$TF_APP_DIR" output -raw admin_user_password 2>/dev/null || true)
    if [ -z "${ADMIN_PASS:-}" ]; then
        echo "ERROR: ADMIN_PASS not set and 'terraform output' returned empty."
        echo "       Set ADMIN_PASS=<password> in the environment or run from a"
        echo "       checkout where terraform/app/ state is available."
        exit 1
    fi
fi

BASE_URL="http://$HOST"

echo "== Camunda dual-region ECS demo =="
echo "Target:    $TARGET ($HOST)"
echo "Process:   $PROCESS_ID"
echo "User:      $ADMIN_USER"
echo ""

# Verify connectivity (8.10 unified REST API requires basic auth on /v2/*).
echo "Verifying gateway connectivity..."
if ! curl -sf -u "$ADMIN_USER:$ADMIN_PASS" "$BASE_URL/v2/topology" > /dev/null; then
    echo "ERROR: Cannot reach gateway at $BASE_URL/v2/topology"
    echo "       Check that the ALB is reachable from this host and that the"
    echo "       credentials are correct."
    exit 1
fi
echo "Gateway is reachable."
echo ""
echo "Creating process instances every 2 seconds (Ctrl+C to stop)..."
echo ""

trap 'echo ""; echo "Stopped."; exit 0' INT TERM

COUNT=0
while true; do
    COUNT=$((COUNT + 1))
    RESPONSE=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" -X POST \
        "$BASE_URL/v2/process-instances" \
        -H "Content-Type: application/json" \
        -d "{\"processDefinitionId\": \"$PROCESS_ID\"}")

    KEY=$(echo "$RESPONSE" | grep -o '"processInstanceKey":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$KEY" ]; then
        echo "[#$COUNT] Instance created: $KEY"
    else
        echo "[#$COUNT] ERROR: $RESPONSE"
    fi

    sleep 2
done
