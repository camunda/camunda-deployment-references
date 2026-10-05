#!/usr/bin/env bash
# Moves the Aurora writer of leftover ECS dual-region test stacks back to
# region 0, so that terraform destroy does not hang on a global cluster whose
# writer a failover test moved away (see the README teardown section). The
# workflow cleanup and the daily cleanup run it before the Terraform destroy.
#
# Usage: restore-aurora-writers.sh <id-substring> <min-age-hours>
#   <id-substring>   only global clusters whose identifier contains it
#   <min-age-hours>  skip stacks younger than this (a test may still be running)
# Env: REGION_0 (home region), AWS_PROFILE / AWS_REGION as for the AWS CLI,
#      AURORA_SETTLE_SECONDS (default 1200) to wait for a running switchover.
#
# Best effort: a failure is logged and the next cluster is tried, so the
# Terraform destroy that follows always runs. With RESTORE_STRICT=true (the Go
# test cleanup), the script still tries every cluster but exits 1 if any
# writer could not be checked or moved home.
set -uo pipefail

MATCH="${1:?id substring required}"
MIN_AGE_HOURS="${2:?minimum age in hours required}"
: "${REGION_0:?REGION_0 must be set}"

# shellcheck source=aws/containers/ecs-dual-region-fargate/procedure/zeebe_management_api.sh
. "$(dirname "$0")/../procedure/zeebe_management_api.sh"

now=$(date -u +%s)
failed=false
done_restoring() {
    [ "${RESTORE_STRICT:-false}" = true ] && [ "$failed" = true ] && exit 1
    exit 0
}
if ! globals=$(aws rds describe-global-clusters --query 'GlobalClusters' --output json); then
    mgmt_err "could not list the Aurora global clusters, terraform destroy may hang."
    failed=true
    done_restoring
fi
while read -r global; do
    id=$(echo "$global" | jq -r .GlobalClusterIdentifier)
    # A switchover still running shows the old writer flag. Let it settle,
    # then decide from the settled membership.
    # A failed read keeps the last known state, so it never looks settled.
    deadline=$((SECONDS + ${AURORA_SETTLE_SECONDS:-1200}))
    while [ -n "$(echo "$global" | jq -r '.FailoverState.Status // ""')" ] && [ "$SECONDS" -lt "$deadline" ]; do
        mgmt_log "$id: switchover in progress, waiting."
        sleep "${AURORA_WRITER_POLL_SECONDS:-15}"
        if fresh=$(aws rds describe-global-clusters --global-cluster-identifier "$id" \
            --query 'GlobalClusters[0]' --output json); then
            global=$fresh
        fi
    done
    if [ -n "$(echo "$global" | jq -r '.FailoverState.Status // ""')" ]; then
        mgmt_err "$id: still switching over, skipping it. terraform destroy may hang."
        failed=true
        continue
    fi
    writer=$(echo "$global" | jq -r '.GlobalClusterMembers[] | select(.IsWriter) | .DBClusterArn')
    home=$(echo "$global" | jq -r --arg r "$REGION_0" \
        '[.GlobalClusterMembers[] | select((.DBClusterArn | split(":")[3]) == $r)][0].DBClusterArn // empty')
    if [ -z "$home" ] || [ "$writer" = "$home" ]; then
        continue
    fi
    if [ "$MIN_AGE_HOURS" -gt 0 ]; then
      if ! created=$(aws rds describe-db-clusters --region "$REGION_0" --db-cluster-identifier "$home" \
        --query 'DBClusters[0].ClusterCreateTime' --output text) ||
        ! created_s=$(date -u -d "$created" +%s 2>/dev/null); then
        mgmt_err "$id: could not read the creation time of $home, skipping it."
        failed=true
        continue
    fi
      if [ $(((now - created_s) / 3600)) -lt "$MIN_AGE_HOURS" ]; then
        mgmt_log "$id: younger than ${MIN_AGE_HOURS}h, skipping."
        continue
      fi
    fi
    mgmt_log "$id: writer is ${writer:-none}, switching it over to $home."
    export AURORA_GLOBAL_CLUSTER_ID="$id"
    if ! aws rds failover-global-cluster --global-cluster-identifier "$id" \
        --target-db-cluster-identifier "$home" --no-cli-pager >/dev/null ||
        ! aurora_wait_writer "$home"; then
        mgmt_err "$id: could not move the writer home, terraform destroy may hang."
        failed=true
    fi
done < <(echo "$globals" | jq -c --arg m "$MATCH" \
    '.[] | select((.GlobalClusterIdentifier | endswith("-global-db")) and (.GlobalClusterIdentifier | contains($m)))')
done_restoring
