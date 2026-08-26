#!/bin/bash
set -euo pipefail

# Description:
# This script deletes ROSA clusters that have no resources left in AWS but still appear in the OpenShift console.
# It ensures that only clusters older than a specified number of hours (MIN_AGE) are deleted.
#
# Usage:
#   cleanup-ghost-rosa-clusters.sh <MIN_AGE in hours>
#   cleanup-ghost-rosa-clusters.sh selftest

# ghost_selftest re-runs this script against stubbed rosa/aws binaries.
#
# It exists for one behaviour in particular: a per-cluster repair that fails
# must not take the rest of the list down with it. Under `set -e` a single
# `rosa create operator-roles` returning CLUSTERS-MGMT-404 used to abort the
# whole script, so every cluster queued behind it was silently skipped and the
# job went red with no cluster deleted.
ghost_selftest() {
  local tmp failures=0 out rc
  tmp=$(mktemp -d)

  _expect() {
    if [[ "$2" == "$3" ]]; then
      echo "ok   $1"
    else
      echo "FAIL $1: got '$2' want '$3'"
      failures=$((failures + 1))
    fi
  }

  mkdir -p "$tmp/bin"
  # Two ghost clusters, both old enough and both missing their installer role.
  # ghost-a repairs cleanly; ghost-b's OIDC config is already gone from RHCS.
  cat >"$tmp/bin/rosa" <<'STUB'
#!/bin/bash
case "$*" in
  "list cluster --output json")
    cat <<'JSON'
[{"id":"a","name":"ghost-a","region":{"id":"eu-west-1"},"creation_timestamp":"2000-01-01T00:00:00Z",
  "status":{"state":"error","limited_support_reason_count":1},"node_pools":{"items":[]},
  "aws":{"sts":{"role_arn":"arn:aws:iam::1:role/ghost-a-account-HCP-ROSA-Installer-Role","oidc_config":{"id":"oidc-a"}}}},
 {"id":"b","name":"ghost-b","region":{"id":"eu-west-1"},"creation_timestamp":"2000-01-01T00:00:00Z",
  "status":{"state":"error","limited_support_reason_count":1},"node_pools":{"items":[]},
  "aws":{"sts":{"role_arn":"arn:aws:iam::1:role/ghost-b-account-HCP-ROSA-Installer-Role","oidc_config":{"id":"oidc-b"}}}}]
JSON
    ;;
  *"create operator-roles"*"oidc-b"*)
    echo "ERR: There was a problem retrieving OIDC Config 'oidc-b': status is 404, code is 'CLUSTERS-MGMT-404'" >&2
    exit 1
    ;;
  "list clusters") ;;                 # nothing registered: both deregister at once
  *) echo "stub rosa $*" ;;
esac
STUB
  cat >"$tmp/bin/aws" <<'STUB'
#!/bin/bash
case "$*" in
  # No installer role exists, so both clusters qualify as orphaned.
  *"list-roles"*) echo "" ;;
  *"get-role"*ghost-a*) echo "arn:aws:iam::1:role/ghost-a-account-HCP-ROSA-Installer-Role" ;;
  *"get-role"*ghost-b*) echo "arn:aws:iam::1:role/ghost-b-account-HCP-ROSA-Installer-Role" ;;
  *"list-open-id-connect-providers"*) echo "None" ;;
  *) echo "" ;;
esac
STUB
  chmod +x "$tmp/bin/rosa" "$tmp/bin/aws"

  # On Darwin the script reaches for `gdate`, which ships with coreutils and is
  # not installed by `just install-tooling`. Now that a pre-commit hook runs
  # this selftest, a macOS checkout without coreutils would fail the hook for a
  # reason that has nothing to do with the change being committed. Shim it: the
  # selftest only needs epoch seconds out of a fixed timestamp.
  cat >"$tmp/bin/gdate" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-d" ]]; then
  python3 -c 'import sys, datetime; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp()))' "$2"
else
  date "$@"
fi
STUB
  chmod +x "$tmp/bin/gdate"

  rc=0
  out=$(PATH="$tmp/bin:$PATH" RHCS_TOKEN=stub \
        DEREGISTER_MAX_ATTEMPTS=1 DEREGISTER_INTERVAL=0 \
        bash "$SELF" 0 2>&1) || rc=$?

  # The point of the fix: ghost-b's stale OIDC config is reported and skipped,
  # and ghost-a is still processed.
  _expect "stale OIDC config is recognised" \
    "$(grep -c 'OIDC config oidc-b is already gone' <<<"$out" || true)" "1"
  _expect "both clusters were processed" \
    "$(grep -c '🔧 Cluster Name:' <<<"$out" || true)" "2"
  _expect "the deletion still ran for both" \
    "$(grep -c '💣 Deleting cluster:' <<<"$out" || true)" "2"
  _expect "a stale OIDC config alone does not fail the run" "$rc" "0"

  rm -rf "$tmp"
  [[ "$failures" -eq 0 ]] || return 1
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

if [[ "${1:-}" == "selftest" ]]; then
  ghost_selftest
  exit $?
fi

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
FAILED=0

# How long to wait for OCM to deregister a cluster before giving up on it.
# Overridable so the behaviour can be exercised without a long wait.
DEREGISTER_MAX_ATTEMPTS="${DEREGISTER_MAX_ATTEMPTS:-30}"
DEREGISTER_INTERVAL="${DEREGISTER_INTERVAL:-30}"

# Checked here rather than at first use: the wait loop only runs after
# `rosa delete cluster`, so a bad value would surface with a deletion already in
# flight — `seq` would print an error and skip the wait entirely, or `sleep`
# would abort the script halfway through a cluster.
if [[ ! "$DEREGISTER_MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "❌ DEREGISTER_MAX_ATTEMPTS must be a positive integer, got '${DEREGISTER_MAX_ATTEMPTS}'." >&2
  exit 1
fi
# 0 is allowed here: it turns the wait into a pure poll, which is how the loop
# gets exercised without spending half an hour asleep.
if [[ ! "$DEREGISTER_INTERVAL" =~ ^[0-9]+$ ]]; then
  echo "❌ DEREGISTER_INTERVAL must be a number of seconds, got '${DEREGISTER_INTERVAL}'." >&2
  exit 1
fi

# age_in_hours prints the whole hours elapsed since a cluster was created.
age_in_hours() {
  local created_at
  created_at=$($date_command -d "$1" +%s)
  echo $(( (CURRENT_TIME - created_at) / 3600 ))
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

# Fetch clusters matching the criteria (if no node pool and error reported)
# The clusters this script repairs are the ones that lost the account role OCM
# needs to tear them down: without it `rosa delete cluster` returns
# CLUSTERS-MGMT-400, terraform can never remove the VPC, and the cluster keeps
# its subnets, Elastic IPs and VPC endpoints until someone recreates the role.
#
# Snapshot every IAM role once rather than probing per cluster. A per-cluster
# `aws iam get-role` scales with the cluster count and adds throttling pressure,
# and a throttled lookup has to be read as "cannot tell", which degrades the
# check precisely when there is most to clean up.
echo "📇 Snapshotting IAM roles..."
if ! EXISTING_ROLES=$(aws iam list-roles --query 'Roles[].RoleName' --output text 2>&1); then
  echo "Error: could not list IAM roles, so no cluster can be judged orphaned:" >&2
  echo "  ${EXISTING_ROLES}" >&2
  exit 1
fi
EXISTING_ROLES=$(printf '%s' "$EXISTING_ROLES" | tr '\t' '\n')

# installer_role_missing answers from that snapshot, using the role ARN OCM
# recorded for the cluster rather than a reconstructed name: a cluster created
# with a different account-role prefix would not match a name pattern, and the
# list this feeds is a list of clusters to delete.
installer_role_missing() {
  local cluster_name="$1"
  local role_arn="$2"
  local role_name

  if [[ -z "$role_arn" || "$role_arn" == "null" ]]; then
    echo "  ⚠️ ${cluster_name} reports no installer role ARN; leaving it alone." >&2
    return 1
  fi
  role_name="${role_arn##*/}"

  grep -qxF "$role_name" <<<"$EXISTING_ROLES" && return 1
  return 0
}

all_clusters=$(rosa list cluster --output json)

# A cluster is a candidate when it shows one of the shapes a failed teardown
# leaves behind:
#   - a ghost: no node pool left and a single limited-support reason;
#   - error;
#   - uninstalling, i.e. a deletion that started and never finished.
# The age gate in the loop below still applies to all of them.
candidates=$(echo "$all_clusters" | jq -c '[.[] | select(
     ((.node_pools.items | length == 0) and .status.limited_support_reason_count == 1)
  or (.status.state == "error")
  or (.status.state == "uninstalling")
)]')

# The fourth shape cannot be expressed in jq because it needs an IAM lookup: a
# cluster in any state whose installer role has gone missing is already
# undeletable, and is the case this script exists to repair.
orphaned=$(echo "$all_clusters" | jq -c '.[]' | while read -r cluster; do
  name=$(echo "$cluster" | jq -r '.name')
  role_arn=$(echo "$cluster" | jq -r '.aws.sts.role_arn // ""')
  created_at=$(echo "$cluster" | jq -r '.creation_timestamp')

  # Apply the age gate before the lookup, not only in the loop below: the probe
  # would otherwise call get-role once per cluster in the account, including the
  # ones just created by a running test, which is how an account with many
  # clusters starts getting IAM throttling errors instead of answers.
  if [ "$(age_in_hours "$created_at")" -lt "$MIN_AGE_HOURS" ]; then
    continue
  fi

  if installer_role_missing "$name" "$role_arn"; then
    echo "$cluster"
  fi
done | jq -c -s '.')

raw_clusters=$(jq -c -n --argjson a "$candidates" --argjson b "$orphaned" '$a + $b | unique_by(.id)')


# Check if there are any clusters
cluster_count=$(echo "$raw_clusters" | jq 'length')

if [ "$cluster_count" -eq 0 ]; then
  echo "✅ No clusters to delete. Exiting."
  exit 0
fi

# Fed through process substitution rather than a pipe: a piped `while` runs in a
# subshell, where the FAILED flag set below would be discarded at the end of the
# loop and the script would exit 0 despite leaving roles behind.
while read -r cluster; do
  cluster_id=$(echo "$cluster" | jq -r '.id')
  cluster_name=$(echo "$cluster" | jq -r '.name')
  region_id=$(echo "$cluster" | jq -r '.region.id')
  oidc_config_id=$(echo "$cluster" | jq -r '.aws.sts.oidc_config.id')
  creation_timestamp=$(echo "$cluster" | jq -r '.creation_timestamp')

  cluster_age_hours=$(age_in_hours "$creation_timestamp")

  if [ "$cluster_age_hours" -lt "$MIN_AGE_HOURS" ]; then
    echo "⏳ Cluster $cluster_name is too recent (${cluster_age_hours}h < ${MIN_AGE_HOURS}h). Skipping."
    continue
  fi



  echo "----------------------------------------"
  echo "🔧 Cluster ID: $cluster_id"
  echo "🔧 Cluster Name: $cluster_name"
  echo "🌍 Region: $region_id"

  echo "📦 Recreating account roles with prefix ${cluster_name}-account"
  if ! account_roles_out=$(AWS_REGION="$region_id" rosa create account-roles \
      --mode auto --yes --hosted-cp --prefix "${cluster_name}-account" 2>&1); then
    echo "$account_roles_out"
    echo "  ❌ Could not recreate account roles for ${cluster_name}; leaving it for the next run."
    FAILED=1
    continue
  fi
  echo "$account_roles_out"

  # Stdout only: this value is passed straight to `--role-arn`, and folding
  # stderr into it would let any AWS CLI warning end up in the flag. Errors
  # still reach the job log, they just do not contaminate the ARN. The shape
  # check is the same guard used on the VPC id in destroy.sh, for the same
  # reason.
  if ! installer_role_arn=$(aws iam get-role \
      --role-name "${cluster_name}-account-HCP-ROSA-Installer-Role" \
      --query 'Role.Arn' --output text); then
    echo "  ❌ Installer role for ${cluster_name} is still missing after the repair; leaving it for the next run."
    FAILED=1
    continue
  fi
  if [[ ! "$installer_role_arn" =~ ^arn:aws:iam::[0-9]+:role/.+$ ]]; then
    echo "  ❌ Unusable installer role ARN for ${cluster_name}: '${installer_role_arn}'; leaving it for the next run."
    FAILED=1
    continue
  fi

  echo "📦 Recreating operator roles with prefix ${cluster_name}-operator"
  if ! operator_roles_out=$(AWS_REGION="$region_id" rosa create operator-roles \
      --mode auto --yes --hosted-cp --prefix "${cluster_name}-operator" \
      --oidc-config-id "${oidc_config_id}" --role-arn "${installer_role_arn}" 2>&1); then
    echo "$operator_roles_out"
    if [[ "$operator_roles_out" == *"CLUSTERS-MGMT-404"* ]]; then
      # RHCS has already dropped this cluster's OIDC config, so there is
      # nothing left for operator roles to reference: the repair is moot, not
      # failed. Deleting the cluster is still worth attempting, and is the
      # whole point of this script.
      echo "  ℹ️ OIDC config ${oidc_config_id} is already gone; skipping the operator-role repair."
    else
      echo "  ❌ Could not recreate operator roles for ${cluster_name}; leaving it for the next run."
      FAILED=1
      continue
    fi
  else
    echo "$operator_roles_out"
  fi

  echo "💣 Deleting cluster: $cluster_name"
  AWS_REGION="$region_id" rosa delete cluster -c "$cluster_name" -y --best-effort --watch

  # Wait for the cluster to be fully deregistered from ROSA API
  # rosa delete cluster can return before the cluster is fully removed,
  # which causes operator-roles deletion to fail with "clusters using Operator Roles Prefix"
  echo "⏳ Waiting for cluster $cluster_name to be fully deregistered..."
  cluster_deregistered=false
  for i in $(seq 1 "$DEREGISTER_MAX_ATTEMPTS"); do
    # Capture `rosa list clusters` separately so we can distinguish a
    # transient failure (API/network hiccup) from a true "cluster not found".
    # Piping it straight into grep loses the exit status: a failed list
    # produces no output, grep does not match, and the cluster is declared
    # deregistered -- which bypasses the guard below and deletes the installer
    # role of a still-live cluster.
    if cluster_list=$(rosa list clusters 2>/dev/null); then
      # Here-string, not `echo ... | grep`: with pipefail a `grep -q` that
      # matches early can kill the producer with SIGPIPE, making the pipeline
      # exit 141 on a *successful* match -- which would take the "deregistered"
      # branch for a cluster that is still there.
      if grep -q "[[:space:]]${cluster_name}[[:space:]]" <<<"$cluster_list"; then
        if [ "$i" -lt "$DEREGISTER_MAX_ATTEMPTS" ]; then
          echo "⏳ Cluster still registered, waiting ${DEREGISTER_INTERVAL}s... (attempt $i/${DEREGISTER_MAX_ATTEMPTS})"
          sleep "$DEREGISTER_INTERVAL"
        else
          echo "❌ Cluster $cluster_name is still registered after $i attempts"
        fi
      else
        echo "✅ Cluster $cluster_name is fully deregistered"
        cluster_deregistered=true
        break
      fi
    elif [ "$i" -lt "$DEREGISTER_MAX_ATTEMPTS" ]; then
      echo "⚠️ rosa list clusters failed transiently, retrying in ${DEREGISTER_INTERVAL}s... (attempt $i/${DEREGISTER_MAX_ATTEMPTS})"
      sleep "$DEREGISTER_INTERVAL"
    else
      # Last attempt: sleeping would delay every cluster for nothing, and
      # claiming a retry that cannot happen misreads the log.
      echo "❌ rosa list clusters still failing after $i attempts; cannot confirm deregistration."
    fi
  done

  if [ "$cluster_deregistered" != true ]; then
    # Deleting the IAM roles now would strip the installer role OCM needs to
    # finish the deletion, turning a cluster that is merely slow into one that
    # can never be removed: `rosa delete cluster` then returns
    # CLUSTERS-MGMT-400, terraform can never delete the VPC, and its Elastic IPs
    # stay allocated until someone recreates the roles by hand. Leave them and
    # let the next run try again, once the cluster has finished uninstalling.
    echo "⚠️ Cluster $cluster_name is still registered; leaving its IAM roles in place."
    echo "   Removing them while OCM still owns the cluster is what makes a cluster undeletable."
    FAILED=1
    continue
  fi

  echo "🧹 Deleting operator roles with prefix ${cluster_name}-operator"
  # Safe to use the rosa CLI here: the cluster is deregistered, so it cannot fail
  # with "clusters using Operator Roles Prefix".
  if ! AWS_REGION="$region_id" rosa delete operator-roles --prefix "${cluster_name}-operator" --yes --mode auto; then
    echo "⚠️ rosa delete operator-roles failed, falling back to direct AWS IAM cleanup"
    cleanup_iam_roles_with_prefix "${cluster_name}-operator"
  fi

  echo "🧹 Deleting account roles with prefix ${cluster_name}-account"
  if ! AWS_REGION="$region_id" rosa delete account-roles --prefix "${cluster_name}-account" --yes --mode auto; then
    echo "⚠️ rosa delete account-roles failed, falling back to direct AWS IAM cleanup"
    cleanup_iam_roles_with_prefix "${cluster_name}-account"
  fi

  echo "🧹 Deleting OIDC provider ${oidc_config_id}"
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

done < <(echo "$raw_clusters" | jq -c '.[]')

if [ "$FAILED" -ne 0 ]; then
  echo "❌ At least one cluster could not be fully cleaned up; its IAM roles were left in place."
  exit 1
fi

echo "✅ Ghost ROSA cluster cleanup finished."
