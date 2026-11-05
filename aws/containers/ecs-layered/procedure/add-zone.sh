#!/usr/bin/env bash
# Adds a zone (a second region) to a running Orchestration Cluster through the management
# API: POST /actuator/cluster/zones/<zone>. The brokers of the new zone must already run
# and have joined the cluster (the camunda layer in the new region), but they host no
# partition until this call.
#
# The management API is not published on the load balancer, so the script tunnels to a
# running broker of the EXISTING zone over ECS Exec, with the helpers of the dual-region
# reference. Needs awscli, the Session Manager plugin, jq and curl.
#
# Usage:
#   add-zone.sh --region <existing region> --ecs-cluster <existing ECS cluster> \
#               --prefix <camunda layer prefix of the existing zone>-oc \
#               --zone zone-b --brokers 3 --replicas 3 --priority 500 [--dry-run]
#
# --dry-run sends dryRun=true: the API validates the change without applying it.
# --force  go on even if GET /actuator/cluster does not list the new brokers. The
#          documentation says they join membership before the zone is added; it does not
#          say whether they appear in that response, so the check is a guard, not a rule.
set -euo pipefail

HELPERS="$(dirname "${BASH_SOURCE[0]}")/../../ecs-dual-region-fargate/procedure/zeebe_management_api.sh"

REGION="" ECS_CLUSTER="" PREFIX="" ZONE="" BROKERS="" REPLICAS="" PRIORITY="" DRY_RUN=false PROFILE="" FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    --ecs-cluster) ECS_CLUSTER="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --zone) ZONE="$2"; shift 2 ;;
    --brokers) BROKERS="$2"; shift 2 ;;
    --replicas) REPLICAS="$2"; shift 2 ;;
    --priority) PRIORITY="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
for v in REGION ECS_CLUSTER PREFIX ZONE BROKERS REPLICAS PRIORITY; do
  [[ -n "${!v}" ]] || { echo "missing --${v//_/-}" >&2; exit 1; }
done
for n in BROKERS REPLICAS PRIORITY; do
  [[ "${!n}" =~ ^[0-9]+$ ]] || { echo "--${n,,} must be a number" >&2; exit 1; }
done

# shellcheck source=/dev/null
. "$HELPERS"

mgmt_tunnel_open "$REGION" "$ECS_CLUSTER" "$PREFIX" "$PROFILE"
trap mgmt_tunnel_close EXIT

mgmt_log "Cluster before the change:"
before="$(mgmt_get /actuator/cluster)"
echo "$before" | jq -c '{brokers: [.brokers[]? | {id, state}] }' || true

# The new brokers must be members already: otherwise the zone would be declared with no
# broker to host its replicas.
joined="$(echo "$before" | jq --arg z "$ZONE" '[.brokers[]? | select((.id|tostring) | startswith($z + "_"))] | length')"
if [[ "$joined" -lt "$BROKERS" ]]; then
  mgmt_err "only ${joined} of ${BROKERS} brokers of ${ZONE} are listed by GET /actuator/cluster. Start them first (camunda layer in the new region) and check the cross-region link, or use --force."
  $FORCE || exit 1
fi

query=""
$DRY_RUN && query="?dryRun=true"
body="$(jq -n --argjson r "$REPLICAS" --argjson p "$PRIORITY" --argjson b "$BROKERS" \
  '{numberOfReplicas: $r, priority: $p, numberOfBrokers: $b}')"

mgmt_log "POST /actuator/cluster/zones/${ZONE}${query}: ${body}"
response="$(mgmt_request POST "/actuator/cluster/zones/${ZONE}${query}" "$body")"
echo "$response" | jq .

$DRY_RUN && { mgmt_log "Dry run only: nothing was changed."; exit 0; }

change_id="$(echo "$response" | jq -r '.changeId')"
mgmt_wait_change "$change_id"

mgmt_log "Cluster after the change:"
mgmt_get /actuator/cluster | jq -c '{zones: .partitioning?, brokers: [.brokers[]? | {id, state}]}' || true
