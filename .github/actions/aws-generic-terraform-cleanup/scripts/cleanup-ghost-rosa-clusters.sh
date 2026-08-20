#!/bin/bash
set -euo pipefail

# Description:
# This script deletes ROSA clusters that have no resources left in AWS but still appear in the OpenShift console.
# It ensures that only clusters older than a specified number of hours (MIN_AGE) are deleted.

# Check if required environment variables are set
if [ -z "$RHCS_TOKEN" ]; then
  echo "Error: The environment variable RHCS_TOKEN is not set."
  exit 1
fi

# Check if MIN_AGE (in hours) is provided
if [ $# -lt 1 ]; then
  echo "❌ Usage: $0 <MIN_AGE in hours>"
  exit 1
fi


# Detect operating system and set the appropriate date command
if [[ "$(uname)" == "Darwin" ]]; then
    date_command="gdate"
else
    date_command="date"
fi

MIN_AGE_HOURS=$1
CURRENT_TIME=$($date_command +%s)

# Number of hours after which a cluster still observed in a deletion/error state
# (no node pools, no AWS resources) is considered "stuck on the Red Hat side".
# Such clusters are no longer retried for deletion: instead they are reported via
# a dedicated alert so the cleanup itself is NOT marked as failed.
STUCK_DELETION_THRESHOLD_HOURS="${STUCK_DELETION_THRESHOLD_HOURS:-24}"

# Region used for the S3 state bucket operations (falls back to AWS_REGION).
AWS_S3_REGION="${AWS_S3_REGION:-${AWS_REGION:-}}"

# Optional S3 location used to persist, across runs, the first time each cluster
# was observed stuck. OCM exposes no deletion-start timestamp, so this external
# state is what lets us measure the ">= STUCK_DELETION_THRESHOLD_HOURS" window.
# When unset, stuck tracking still works within a single run but cannot span runs.
STUCK_STATE_BUCKET="${STUCK_STATE_BUCKET:-}"
STUCK_STATE_KEY="${STUCK_STATE_KEY:-}"

# Local working copy of the persisted state file.
STUCK_STATE_FILE="$(mktemp)"

# load_stuck_state downloads the persisted first-seen state from S3 into
# STUCK_STATE_FILE, defaulting to an empty object when missing or invalid.
load_stuck_state() {
  if [[ -n "$STUCK_STATE_BUCKET" && -n "$STUCK_STATE_KEY" ]]; then
    local src="s3://${STUCK_STATE_BUCKET}/${STUCK_STATE_KEY}"
    if [[ -n "$AWS_S3_REGION" ]]; then
      aws s3 cp "$src" "$STUCK_STATE_FILE" --region "$AWS_S3_REGION" >/dev/null 2>&1 || true
    else
      aws s3 cp "$src" "$STUCK_STATE_FILE" >/dev/null 2>&1 || true
    fi
  fi
  if ! jq empty "$STUCK_STATE_FILE" >/dev/null 2>&1; then
    echo '{}' > "$STUCK_STATE_FILE"
  fi
}

# save_stuck_state writes the given JSON state back to S3 (best-effort).
save_stuck_state() {
  local new_state="$1"
  printf '%s' "$new_state" > "$STUCK_STATE_FILE"
  if [[ -n "$STUCK_STATE_BUCKET" && -n "$STUCK_STATE_KEY" ]]; then
    local dst="s3://${STUCK_STATE_BUCKET}/${STUCK_STATE_KEY}"
    local copied=true
    if [[ -n "$AWS_S3_REGION" ]]; then
      aws s3 cp "$STUCK_STATE_FILE" "$dst" --region "$AWS_S3_REGION" >/dev/null 2>&1 || copied=false
    else
      aws s3 cp "$STUCK_STATE_FILE" "$dst" >/dev/null 2>&1 || copied=false
    fi
    if [[ "$copied" == true ]]; then
      echo "💾 Persisted stuck-cluster state to $dst"
    else
      echo "⚠️ Failed to persist stuck-cluster state to $dst (continuing)"
    fi
  fi
}


# cleanup_iam_roles_with_prefix removes all IAM roles whose name starts with the
# given prefix, including detaching/deleting their policies first.
cleanup_iam_roles_with_prefix() {
  local role_prefix="$1"
  local roles
  roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '${role_prefix}')].RoleName" --output text)
  if [[ -z "$roles" || "$roles" == "None" ]]; then
    echo "  ℹ️ No IAM roles found for prefix ${role_prefix}, already cleaned up"
    return 0
  fi
  for role in $roles; do
    echo "  🗑️ Cleaning up IAM role: $role"
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text)
    if [[ -n "$attached_policies" && "$attached_policies" != "None" ]]; then
      for policy_arn in $attached_policies; do
        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
      done
    fi
    local inline_policies
    inline_policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text)
    if [[ -n "$inline_policies" && "$inline_policies" != "None" ]]; then
      for policy_name in $inline_policies; do
        aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name"
      done
    fi
    aws iam delete-role --role-name "$role"
    echo "  ✅ Deleted role: $role"
  done
}

rosa login --token="$RHCS_TOKEN"

# Ensure account-level OCM roles exist (prerequisites for cluster operations)
echo "📦 Ensuring account-roles exist..."
rosa create account-roles --mode auto --yes
echo "📦 Ensuring ocm-role exists..."
rosa create ocm-role --mode auto --yes

# Fetch clusters matching the criteria: no node pools left and either reported in
# limited support, in "error" state, or already "uninstalling" (deletion in
# progress / potentially stuck on the Red Hat side).
raw_clusters=$(rosa list cluster --output json | jq '[.[] | select((.node_pools.items | length == 0) and ((.status.limited_support_reason_count == 1) or (.status.state == "error") or (.status.state == "uninstalling")))]')

# Check if there are any clusters
cluster_count=$(echo "$raw_clusters" | jq 'length')
echo "🔎 Found ${cluster_count} candidate cluster(s) in a stuck/error/uninstalling state."

# Load the cross-run first-seen state so we can measure how long each cluster has
# been stuck.
load_stuck_state
NOW_ISO=$($date_command -u +%Y-%m-%dT%H:%M:%SZ)

# new_state is rebuilt from the clusters seen this run, so entries for clusters
# that disappeared (successfully deleted) are pruned automatically.
new_state='{}'
clusters_to_delete=()
stuck_cluster_names=()

# Pass 1: classify every candidate cluster. This pass performs no destructive
# action, so the refreshed state and the stuck list can be persisted/emitted
# before any deletion is attempted (a later deletion failure must not lose them).
while read -r cluster; do
  cluster_id=$(echo "$cluster" | jq -r '.id')
  cluster_name=$(echo "$cluster" | jq -r '.name')
  cluster_state=$(echo "$cluster" | jq -r '.status.state')
  creation_timestamp=$(echo "$cluster" | jq -r '.creation_timestamp')

  # Convert creation timestamp to UNIX time
  cluster_created_time=$($date_command -d "$creation_timestamp" +%s)
  cluster_age_hours=$(( (CURRENT_TIME - cluster_created_time) / 3600 ))

  # First time this cluster was observed stuck (carried over from previous runs).
  first_seen=$(jq -r --arg id "$cluster_id" '.[$id].first_seen // ""' "$STUCK_STATE_FILE")
  if [[ -z "$first_seen" ]]; then
    first_seen="$NOW_ISO"
  fi
  first_seen_epoch=$($date_command -d "$first_seen" +%s 2>/dev/null || echo "$CURRENT_TIME")
  stuck_hours=$(( (CURRENT_TIME - first_seen_epoch) / 3600 ))

  # Carry the (possibly newly recorded) first_seen forward into the new state.
  new_state=$(echo "$new_state" | jq --arg id "$cluster_id" --arg name "$cluster_name" --arg ts "$first_seen" '.[$id] = {name: $name, first_seen: $ts}')

  echo "----------------------------------------"
  echo "🔍 Cluster: $cluster_name ($cluster_id) — state=$cluster_state, age=${cluster_age_hours}h, stuck_for=${stuck_hours}h"

  # 1. Stuck for too long → stop retrying, flag for a dedicated alert. Do NOT fail.
  if [ "$stuck_hours" -ge "$STUCK_DELETION_THRESHOLD_HOURS" ]; then
    echo "🚨 Cluster $cluster_name has been stuck for ${stuck_hours}h (>= ${STUCK_DELETION_THRESHOLD_HOURS}h). Skipping deletion and flagging for a dedicated alert."
    stuck_cluster_names+=("$cluster_name")
    continue
  fi

  # 2. Deletion already in progress at Red Hat → let it run, re-check next time.
  #    Re-issuing "rosa delete cluster" here would error and fail the whole cleanup.
  if [ "$cluster_state" == "uninstalling" ]; then
    echo "⏳ Cluster $cluster_name is already uninstalling (${stuck_hours}h < ${STUCK_DELETION_THRESHOLD_HOURS}h). Letting Red Hat finish; will re-check next run."
    continue
  fi

  # 3. Too recent ghost cluster → skip for now (existing safety check).
  if [ "$cluster_age_hours" -lt "$MIN_AGE_HOURS" ]; then
    echo "⏳ Cluster $cluster_name is too recent (${cluster_age_hours}h < ${MIN_AGE_HOURS}h). Skipping."
    continue
  fi

  # 4. Genuine ghost cluster to delete in pass 2.
  clusters_to_delete+=("$cluster")
done < <(echo "$raw_clusters" | jq -c '.[]')

# Persist refreshed state and emit the stuck list BEFORE any destructive action.
save_stuck_state "$new_state"

stuck_joined=""
if [ "${#stuck_cluster_names[@]}" -gt 0 ]; then
  stuck_joined=$(printf '%s, ' "${stuck_cluster_names[@]}")
  stuck_joined=${stuck_joined%, }
  echo "🚨 Clusters stuck in deletion for >= ${STUCK_DELETION_THRESHOLD_HOURS}h: ${stuck_joined}"
fi
# Surface the stuck list to the calling GitHub Action step so the workflow can
# raise a dedicated Slack alert without failing the cleanup.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "stuck_clusters=${stuck_joined}" >> "$GITHUB_OUTPUT"
fi

if [ "${#clusters_to_delete[@]}" -eq 0 ]; then
  echo "✅ No ghost clusters require deletion."
  exit 0
fi

# Pass 2: delete the genuine ghost clusters. Failures here keep the existing
# semantics (the script exits non-zero and the cleanup is retried/alerted).
for cluster in "${clusters_to_delete[@]}"; do
  cluster_id=$(echo "$cluster" | jq -r '.id')
  cluster_name=$(echo "$cluster" | jq -r '.name')
  region_id=$(echo "$cluster" | jq -r '.region.id')
  oidc_config_id=$(echo "$cluster" | jq -r '.aws.sts.oidc_config.id')

  echo "----------------------------------------"
  echo "🔧 Cluster ID: $cluster_id"
  echo "🔧 Cluster Name: $cluster_name"
  echo "🌍 Region: $region_id"

  echo "📦 Recreating account roles with prefix ${cluster_name}-account"
  AWS_REGION="$region_id" rosa create account-roles --mode auto --yes --hosted-cp --prefix "${cluster_name}-account"

  installer_role_arn=$(aws iam get-role --role-name "${cluster_name}-account-HCP-ROSA-Installer-Role" --query 'Role.Arn' --output text)

  echo "📦 Recreating operator roles with prefix ${cluster_name}-operator"
  AWS_REGION="$region_id" rosa create operator-roles --mode auto --yes --hosted-cp --prefix "${cluster_name}-operator" --oidc-config-id "${oidc_config_id}" --role-arn "${installer_role_arn}"

  echo "💣 Deleting cluster: $cluster_name"
  # Do NOT pass --watch: it blocks for the full ~60 min AWS teardown and
  # starves later clusters in the matrix. The polling loop below is the
  # supported wait mechanism.
  AWS_REGION="$region_id" rosa delete cluster -c "$cluster_name" -y --best-effort

  # Wait for the cluster to be fully deregistered from ROSA API
  # rosa delete cluster can return before the cluster is fully removed,
  # which causes operator-roles deletion to fail with "clusters using Operator Roles Prefix"
  echo "⏳ Waiting for cluster $cluster_name to be fully deregistered..."
  cluster_deregistered=false
  for i in $(seq 1 60); do
    # Capture `rosa list clusters` separately so we can distinguish a
    # transient failure (API/network hiccup) from a true "cluster not found".
    # Treating a non-zero `rosa list` as deregistered would let role deletion
    # race ahead of cluster teardown and fail with
    # "clusters using Operator Roles Prefix".
    if cluster_list=$(rosa list clusters 2>/dev/null); then
      if echo "$cluster_list" | grep -q "[[:space:]]${cluster_name}[[:space:]]"; then
        if [ "$i" -lt 60 ]; then
          echo "⏳ Cluster still registered, waiting 30s... (attempt $i/60)"
          sleep 30
        else
          echo "❌ Cluster $cluster_name is still registered after $i attempts"
        fi
      else
        echo "✅ Cluster $cluster_name is fully deregistered"
        cluster_deregistered=true
        break
      fi
    else
      echo "⚠️ rosa list clusters failed transiently, retrying in 30s... (attempt $i/60)"
      sleep 30
    fi
  done

  if [ "$cluster_deregistered" != true ]; then
    echo "⚠️ Cluster $cluster_name did not deregister in time. Proceeding with direct IAM cleanup..."
  fi

  echo "🧹 Deleting operator roles with prefix ${cluster_name}-operator"
  if [ "$cluster_deregistered" == true ]; then
    # Only try rosa CLI if the cluster is fully deregistered, otherwise it will fail
    # with "clusters using Operator Roles Prefix"
    if ! AWS_REGION="$region_id" rosa delete operator-roles --prefix "${cluster_name}-operator" --yes --mode auto; then
      echo "⚠️ rosa delete operator-roles failed, falling back to direct AWS IAM cleanup"
      cleanup_iam_roles_with_prefix "${cluster_name}-operator"
    fi
  else
    echo "⚠️ Cluster still registered, falling back to direct AWS IAM cleanup for operator roles"
    cleanup_iam_roles_with_prefix "${cluster_name}-operator"
  fi

  echo "🧹 Deleting account roles with prefix ${cluster_name}-account"
  if [ "$cluster_deregistered" == true ]; then
    if ! AWS_REGION="$region_id" rosa delete account-roles --prefix "${cluster_name}-account" --yes --mode auto; then
      echo "⚠️ rosa delete account-roles failed, falling back to direct AWS IAM cleanup"
      cleanup_iam_roles_with_prefix "${cluster_name}-account"
    fi
  else
    echo "⚠️ Cluster still registered, falling back to direct AWS IAM cleanup for account roles"
    cleanup_iam_roles_with_prefix "${cluster_name}-account"
  fi

  echo "🧹 Deleting OIDC provider ${oidc_config_id}"
  if [ "$cluster_deregistered" == true ]; then
    if ! AWS_REGION="$region_id" rosa delete oidc-provider --oidc-config-id "${oidc_config_id}" --yes --mode auto; then
      echo "⚠️ rosa delete oidc-provider failed, falling back to direct AWS IAM cleanup"
      oidc_provider_arn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, '/${oidc_config_id}')].Arn" --output text)
      if [[ -n "$oidc_provider_arn" && "$oidc_provider_arn" != "None" ]]; then
        echo "  🗑️ Deleting OIDC provider: $oidc_provider_arn"
        aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$oidc_provider_arn"
        echo "  ✅ Deleted OIDC provider: $oidc_provider_arn"
      else
        echo "  ℹ️ No OIDC provider found for config ID ${oidc_config_id}, already cleaned up"
      fi
    fi
  else
    echo "⚠️ Cluster still registered, falling back to direct AWS IAM cleanup for OIDC provider"
    oidc_provider_arn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, '/${oidc_config_id}')].Arn" --output text)
    if [[ -n "$oidc_provider_arn" && "$oidc_provider_arn" != "None" ]]; then
      echo "  🗑️ Deleting OIDC provider: $oidc_provider_arn"
      aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$oidc_provider_arn"
      echo "  ✅ Deleted OIDC provider: $oidc_provider_arn"
    else
      echo "  ℹ️ No OIDC provider found for config ID ${oidc_config_id}, already cleaned up"
    fi
  fi

done

echo "✅ Ghost ROSA cluster cleanup completed."
