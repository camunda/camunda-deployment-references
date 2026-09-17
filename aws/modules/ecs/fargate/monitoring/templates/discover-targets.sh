#!/bin/sh
# Discover Camunda orchestration-cluster targets from AWS Cloud Map namespaces
# and write them as a Prometheus file_sd_configs JSON document.
#
# Prometheus on ECS has no equivalent of the Kubernetes service-discovery
# roles, and hardcoding task IPs does not survive a redeployment. This sidecar
# closes that gap: it queries the Cloud Map API (servicediscovery) for private
# DNS namespaces matching NAMESPACE_SUFFIX, lists the registered instances of
# SERVICE_NAME in each, and writes their IPs to a file Prometheus hot-reloads.
# Reading the API rather than DNS means no resolver tooling is needed in the
# image, and each task is emitted separately so it keeps its own task-id label.
#
# NOTE: deliberately no "set -e". This is a long-running sidecar and the
# container is marked essential, so letting a transient AWS API error abort the
# script would take the whole Fargate task down with it.

TARGETS_FILE="${TARGETS_FILE:-/etc/prometheus/targets/targets.json}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-30}"
PORT="${PORT:-9600}"
METRICS_PATH="${METRICS_PATH:-/actuator/prometheus}"
NAMESPACE_SUFFIX="${NAMESPACE_SUFFIX:-.service.local}"
SERVICE_NAME="${SERVICE_NAME:-orchestration-cluster}"
VPC_ID="${VPC_ID:-}"
TMPDIR="${TMPDIR:-/tmp}"

mkdir -p "$(dirname "$TARGETS_FILE")"

# Write an empty target list straight away so Prometheus starts cleanly instead
# of failing on a missing file during the first discovery cycle.
echo "[]" > "$TARGETS_FILE"

while true; do
    echo "--- Discovery cycle starting ---"
    echo "Region: ${AWS_DEFAULT_REGION:-<not set>}, namespace suffix: ${NAMESPACE_SUFFIX}, service: ${SERVICE_NAME}"

    # --output text yields tab-separated "ns-xxxx<TAB>name.service.local" lines.
    NS_FILE="${TMPDIR}/namespaces.txt"
    if ! aws servicediscovery list-namespaces \
        --filters Name=TYPE,Values=DNS_PRIVATE \
        --query 'Namespaces[].[Id,Name]' --output text > "$NS_FILE" 2> "${TMPDIR}/ns-error.txt"; then
        echo "ERROR: list-namespaces failed: $(cat "${TMPDIR}/ns-error.txt")"
    fi

    # The AWS CLI prints "None" when a query matches nothing.
    sed -i '/^None$/d' "$NS_FILE"
    NS_COUNT=$(grep -c . "$NS_FILE" 2> /dev/null || echo 0)
    echo "Found ${NS_COUNT} private DNS namespace(s)"

    TARGETS="["
    FIRST=true

    # Fed by redirection rather than a pipe, so the loop body stays in this
    # shell and the TARGETS accumulator survives the iteration.
    while IFS="	" read -r NS_ID NS_NAME; do
        [ -z "$NS_ID" ] && continue

        # Only namespaces the operator asked for. An empty suffix is rejected
        # by the module's variable validation, so this cannot match everything.
        case "$NS_NAME" in
            *"$NAMESPACE_SUFFIX") ;;
            *) continue ;;
        esac

        echo "  Checking namespace: ${NS_NAME} (${NS_ID})"

        # list-namespaces is account and region wide, so a namespace with the
        # same suffix in another VPC would otherwise be scraped: its addresses
        # are unreachable from here and would pollute the series. A private DNS
        # namespace is backed by a Route 53 hosted zone, whose VPC associations
        # are what actually decide reachability.
        if [ -n "$VPC_ID" ]; then
            HZ_ID=$(aws servicediscovery get-namespace --id "$NS_ID" \
                --query 'Namespace.Properties.DnsProperties.HostedZoneId' \
                --output text 2> /dev/null || echo "None")

            if [ -z "$HZ_ID" ] || [ "$HZ_ID" = "None" ]; then
                echo "    Could not resolve the hosted zone, skipping"
                continue
            fi

            ASSOCIATED=$(aws route53 get-hosted-zone --id "$HZ_ID" \
                --query "length(VPCs[?VPCId=='${VPC_ID}'])" \
                --output text 2> /dev/null || echo "0")

            if [ "$ASSOCIATED" = "0" ] || [ "$ASSOCIATED" = "None" ]; then
                echo "    Not associated with ${VPC_ID}, skipping"
                continue
            fi
        fi

        SVC_ID=$(aws servicediscovery list-services \
            --filters Name=NAMESPACE_ID,Values="$NS_ID" \
            --query "Services[?Name=='${SERVICE_NAME}'].Id | [0]" \
            --output text 2> /dev/null || echo "None")

        if [ -z "$SVC_ID" ] || [ "$SVC_ID" = "None" ]; then
            echo "    No ${SERVICE_NAME} service found, skipping"
            continue
        fi

        echo "    Found service: ${SVC_ID}"

        # ECS registers each task with InstanceId = task id and an
        # AWS_INSTANCE_IPV4 attribute.
        INSTANCES_FILE="${TMPDIR}/instances.txt"
        aws servicediscovery list-instances \
            --service-id "$SVC_ID" \
            --query 'Instances[].[Id,Attributes.AWS_INSTANCE_IPV4]' \
            --output text > "$INSTANCES_FILE" 2> /dev/null || true

        INSTANCE_COUNT=$(grep -c . "$INSTANCES_FILE" 2> /dev/null || echo 0)
        if [ "$INSTANCE_COUNT" -eq 0 ] || [ "$(cat "$INSTANCES_FILE")" = "None" ]; then
            echo "    No instances registered, skipping"
            continue
        fi

        # "benchmark1-oc.service.local" -> "benchmark1-oc"
        CLUSTER=$(echo "$NS_NAME" | sed 's/\.service\.local$//')
        echo "    Discovered ${INSTANCE_COUNT} instance(s) for ${CLUSTER}"

        # One target group per instance, so every task keeps its own label set
        # and Prometheus can tell the brokers apart.
        while IFS="	" read -r TASK_ID IP; do
            if [ -z "$IP" ] || [ "$IP" = "None" ]; then
                continue
            fi

            # "arn:aws:ecs:...:task/cluster/abc123" -> "abc123"
            SHORT_TASK_ID=$(echo "$TASK_ID" | sed 's|.*/||')

            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                TARGETS="${TARGETS},"
            fi

            TARGETS="${TARGETS}
  {
    \"targets\": [\"${IP}:${PORT}\"],
    \"labels\": {
      \"namespace\": \"ecs-${CLUSTER}\",
      \"cluster\": \"ecs\",
      \"pod\": \"${SHORT_TASK_ID}\",
      \"__metrics_path__\": \"${METRICS_PATH}\"
    }
  }"
        done < "$INSTANCES_FILE"
    done < "$NS_FILE"

    TARGETS="${TARGETS}
]"

    # Write then move, so Prometheus never reads a half-written file.
    echo "$TARGETS" > "${TARGETS_FILE}.tmp"
    mv "${TARGETS_FILE}.tmp" "$TARGETS_FILE"

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Targets written to ${TARGETS_FILE}"
    sleep "$REFRESH_INTERVAL"
done
