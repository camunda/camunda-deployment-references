#!/bin/bash
# Applies the layers in order and passes the outputs of each layer to the next one as
# variables. This script is the only place that knows the wiring: every layer is a plain
# Terraform root that takes variables, so you can run one on its own, skip one, or
# replace one with something you already have (see examples/byo-vpc).
#
# Usage: [PLAN=cluster|management] compose.sh <apply|plan|destroy> <config-dir>
#
#   PLAN=cluster      (default) network, compute, object storage, storage, exposure, identity and
#                     the Camunda layer: one Orchestration Cluster.
#   PLAN=management   network, compute, storage, exposure, OIDC provider, Management Identity and
#                     Camunda Hub: the management plane, deployed once for all clusters.
#
# <config-dir> holds one <layer>.tfvars per layer that you configure yourself.
#
# Bring your own VPC without skipping the layer: run the network layer with
# byo_vpc = true. It creates nothing, validates your IDs and exposes them in the same
# outputs, so the layers after it do not know the difference.
#
# SKIP_LAYERS="exposure identity"   layers you replace entirely. The layers after them
#                                   then need the values they would have received, in
#                                   their own <layer>.tfvars, following the layer contract.
#
# plan only works once the layers before it have been applied: their outputs are the
# inputs of the next one.
#
# Environment:
#   TF_STATE_BUCKET, TF_STATE_REGION   S3 backend of the layers (key: <layer>/terraform.tfstate)
#   WORK_DIR                           where generated files go (default ./debug)
#   STATE_KEY_PREFIX                   prefix of the state keys, for a second deployment
#                                      (for example "region-b/") that must not share state
#   STORAGE_OUTPUTS_FILE               JSON of `terraform output -json` to use as the outputs
#                                      of the storage layer, when the database is not created
#                                      by this run (the global-database root in a second region)
set -euo pipefail

ACTION="${1:?usage: compose.sh <apply|plan|destroy> <config-dir>}"
CONFIG_DIR="$(cd "${2:?usage: compose.sh <apply|plan|destroy> <config-dir>}" && pwd)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
WORK_DIR="${WORK_DIR:-./debug}"
SKIP_LAYERS="${SKIP_LAYERS:-}"
STATE_KEY_PREFIX="${STATE_KEY_PREFIX:-}"
STORAGE_OUTPUTS_FILE="${STORAGE_OUTPUTS_FILE:-}"
: "${TF_STATE_BUCKET:?set TF_STATE_BUCKET}"
: "${TF_STATE_REGION:?set TF_STATE_REGION}"

PLAN="${PLAN:-cluster}"
case "$PLAN" in
  cluster) LAYERS=(network compute object-storage storage exposure identity camunda) ;;
  management) LAYERS=(network compute storage exposure oidc-provider management-identity hub) ;;
  *)
    echo "unknown PLAN: $PLAN" >&2
    exit 1
    ;;
esac
OUT="$WORK_DIR/layers"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

case "$ACTION" in
  apply | plan) ORDER=("${LAYERS[@]}") ;;
  destroy)
    ORDER=()
    for ((i = ${#LAYERS[@]} - 1; i >= 0; i--)); do ORDER+=("${LAYERS[i]}"); done
    ;;
  *)
    echo "unknown action: $ACTION" >&2
    exit 1
    ;;
esac

skipped() {
  [[ " $SKIP_LAYERS " == *" $1 "* ]]
}

# Output of an already applied layer, as JSON ({} when it was skipped or never applied).
outputs_of() {
  if [[ "$1" == "storage" && -n "$STORAGE_OUTPUTS_FILE" ]]; then
    cat "$STORAGE_OUTPUTS_FILE"
  elif [[ -f "$OUT/$1.outputs.json" ]]; then cat "$OUT/$1.outputs.json"; else echo '{}'; fi
}

# The variables a layer takes from the layers before it. The names on the left are the
# layer's variables, the expressions on the right are the previous layers' outputs.
wiring_for() {
  local layer="$1"
  local network compute objects storage exposure identity oidc_provider mgmt_identity
  network="$(outputs_of network)"
  compute="$(outputs_of compute)"
  objects="$(outputs_of object-storage)"
  storage="$(outputs_of storage)"
  exposure="$(outputs_of exposure)"
  identity="$(outputs_of identity)"
  oidc_provider="$(outputs_of oidc-provider)"
  mgmt_identity="$(outputs_of management-identity)"

  case "$layer" in
    network | object-storage) echo '{}' ;;
    compute)
      jq -n --argjson n "$network" '{vpc_id: $n.vpc_id.value, vpc_cidr: $n.vpc_cidr.value}'
      ;;
    storage)
      jq -n --argjson n "$network" --argjson c "$compute" '{
        vpc_id: $n.vpc_id.value, vpc_cidr: $n.vpc_cidr.value,
        private_subnet_ids: $n.private_subnet_ids.value,
        ecs_cluster_arn: $c.ecs_cluster_arn.value,
        task_execution_role_arn: $c.task_execution_role_arn.value,
        task_execution_role_name: $c.task_execution_role_name.value,
        secrets_kms_key_arn: $c.secrets_kms_key_arn.value,
        seed_security_group_ids: [$c.camunda_ports_security_group_id.value, $c.egress_security_group_id.value]}'
      ;;
    exposure)
      jq -n --argjson n "$network" --argjson c "$compute" '{
        vpc_id: $n.vpc_id.value, public_subnet_ids: $n.public_subnet_ids.value,
        private_subnet_ids: $n.private_subnet_ids.value,
        camunda_ports_security_group_id: $c.camunda_ports_security_group_id.value}'
      ;;
    identity)
      jq -n --argjson c "$compute" --argjson e "$exposure" '{
        task_execution_role_name: $c.task_execution_role_name.value,
        secrets_kms_key_arn: $c.secrets_kms_key_arn.value,
        public_base_url: $e.public_base_url.value}'
      ;;
    oidc-provider | management-identity | hub)
      # The components of the management plane share one wiring: where they run, how they are
      # exposed, and the database that the storage layer made for them.
      local db_key
      case "$layer" in
        oidc-provider) db_key=oidc_provider ;;
        management-identity) db_key=management_identity ;;
        hub) db_key=camunda_hub ;;
      esac
      jq -n --arg db_key "$db_key" --arg layer "$layer" \
        --argjson n "$network" --argjson c "$compute" --argjson s "$storage" --argjson e "$exposure" \
        --argjson o "$oidc_provider" --argjson m "$mgmt_identity" '{
        vpc_id: $n.vpc_id.value, private_subnet_ids: $n.private_subnet_ids.value,
        ecs_cluster_id: $c.ecs_cluster_id.value,
        task_execution_role_arn: $c.task_execution_role_arn.value,
        task_execution_role_name: $c.task_execution_role_name.value,
        secrets_kms_key_arn: $c.secrets_kms_key_arn.value,
        registry_credentials_arn: $c.registry_credentials_arn.value,
        camunda_ports_security_group_id: $c.camunda_ports_security_group_id.value,
        egress_security_group_id: $c.egress_security_group_id.value,
        service_connect_namespace_arn: $c.service_connect_namespace_arn.value,
        log_group_name: $c.components_log_group_name.value,
        alb_listener_http_webapp_arn: $e.alb_listener_http_webapp_arn.value,
        public_base_url: $e.public_base_url.value,
        database: $s.databases.value[$db_key],
        db_seed_done: $s.db_seed_done.value}
        + (if $layer == "oidc-provider" then {} else {oidc: $o.management.value} end)
        + (if $layer == "hub" then {
            management_identity_url: $m.internal_url.value,
            management_identity_hub_authorization_enabled: $m.hub_authorization_enabled.value
          } else {} end)'
      ;;
    camunda)
      local zone
      zone="$(grep -E '^zone[[:space:]]*=' "$CONFIG_DIR/camunda.tfvars" 2>/dev/null | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' || true)"
      zone="${zone:-zone-a}"
      jq -n --arg zone "$zone" --argjson n "$network" --argjson c "$compute" --argjson o "$objects" \
        --argjson s "$storage" --argjson e "$exposure" --argjson i "$identity" '{
        vpc_id: $n.vpc_id.value, private_subnet_ids: $n.private_subnet_ids.value,
        ecs_cluster_id: $c.ecs_cluster_id.value,
        task_execution_role_arn: $c.task_execution_role_arn.value,
        task_execution_role_name: $c.task_execution_role_name.value,
        secrets_kms_key_arn: $c.secrets_kms_key_arn.value,
        registry_credentials_arn: $c.registry_credentials_arn.value,
        camunda_ports_security_group_id: $c.camunda_ports_security_group_id.value,
        egress_security_group_id: $c.egress_security_group_id.value,
        efs_security_group_id: $c.efs_security_group_id.value,
        backup_bucket_name: $o.backup_bucket_name.value,
        backup_access_policy_arn: $o.backup_access_policy_arn.value,
        lease_bucket: $o.lease_buckets.value[$zone],
        secondary_storage: $s.secondary_storage.value,
        rds_db_connect_policy_arn: $s.rds_db_connect_policy_arns.value.camunda,
        db_seed_done: $s.db_seed_done.value,
        alb_listener_http_webapp_arn: $e.alb_listener_http_webapp_arn.value,
        alb_listener_http_management_arn: $e.alb_listener_http_management_arn.value,
        nlb_grpc_arn: $e.nlb_grpc_arn.value,
        raft_nlb_arn: ($e.nlb_raft_arn.value // ""),
        oidc: $i.oidc.value}'
      ;;
  esac
}

for layer in "${ORDER[@]}"; do
  if skipped "$layer"; then
    echo "== $layer: skipped (SKIP_LAYERS)"
    continue
  fi

  dir="$ROOT/$layer"
  wiring="$OUT/$layer.wiring.tfvars.json"
  wiring_for "$layer" >"$wiring"

  args=(-var-file="$wiring")
  [[ -f "$CONFIG_DIR/$layer.tfvars" ]] && args+=(-var-file="$CONFIG_DIR/$layer.tfvars")

  echo "== $layer: terraform $ACTION"
  terraform -chdir="$dir" init -input=false -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="region=$TF_STATE_REGION" \
    -backend-config="key=${STATE_KEY_PREFIX}$layer/terraform.tfstate" >/dev/null

  case "$ACTION" in
    apply)
      terraform -chdir="$dir" apply -input=false -auto-approve "${args[@]}"
      terraform -chdir="$dir" output -json >"$OUT/$layer.outputs.json"
      ;;
    plan)
      terraform -chdir="$dir" plan -input=false "${args[@]}"
      ;;
    destroy)
      terraform -chdir="$dir" destroy -input=false -auto-approve "${args[@]}"
      ;;
  esac
done
