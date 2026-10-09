#!/usr/bin/env bash
# Prepares the Aurora global cluster of leftover ECS dual-region test stacks
# for terraform destroy: moves a writer that a failover test moved away back to
# region 0 (see the README teardown section), then detaches the readers, so the
# destroy cannot hang on the writer's last instance. The workflow cleanup and
# the daily cleanup run it before the Terraform destroy.
#
# Usage: restore-aurora-writers.sh <id-regex> <min-age-hours>
#   <id-regex>       only global clusters whose identifier matches it (jq
#                    regex). Identifiers must also follow the test naming,
#                    ^e2e-<label>-<suffix>-global-db$, so no other stack is
#                    ever touched. With RESTORE_EXACT_ID=true (the Go
#                    test cleanup), <id-regex> is instead the exact identifier
#                    of one global cluster, whatever its naming.
#   <min-age-hours>  skip stacks younger than this (a test may still be running)
# Env: REGION_0 (home region), AWS_PROFILE / AWS_REGION as for the AWS CLI,
#      AURORA_SETTLE_SECONDS (default 1200): the whole budget of one cluster,
#      shared by settling a running switchover, retrying while replication
#      sets up, and waiting for the move home.
#      RESTORE_BUDGET_SECONDS (default unlimited): the budget of the whole run.
#      A cluster is only started if a full per-cluster budget still fits, so
#      a step timeout set above it never kills a switchover midway.
#
# Best effort: a failure is logged and the next cluster is tried, so the
# Terraform destroy that follows always runs. With RESTORE_STRICT=true (the Go
# test cleanup), the script still tries every cluster but exits 1 if any
# writer could not be checked or moved home.
set -uo pipefail

MATCH="${1:?identifier regex required}"
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
# A malformed value would make the age test error out and skip the age gate.
if ! [[ "$MIN_AGE_HOURS" =~ ^[0-9]{1,4}$ ]]; then
    mgmt_err "minimum age '$MIN_AGE_HOURS' is not a whole number of hours (0-9999), restoring nothing."
    failed=true
    done_restoring
fi
if ! globals=$(aws rds describe-global-clusters --query 'GlobalClusters' --output json); then
    mgmt_err "could not list the Aurora global clusters, terraform destroy may hang."
    failed=true
    done_restoring
fi
cluster_budget=${AURORA_SETTLE_SECONDS:-1200}
while read -r global; do
    id=$(echo "$global" | jq -r .GlobalClusterIdentifier)
    if [ -n "${RESTORE_BUDGET_SECONDS:-}" ] && [ $((SECONDS + cluster_budget)) -gt "$RESTORE_BUDGET_SECONDS" ]; then
        mgmt_err "$id: not enough run budget left for another cluster, skipping it. terraform destroy may hang."
        failed=true
        continue
    fi
    deadline=$((SECONDS + cluster_budget))
    # A switchover still running shows the old writer flag. Let it settle,
    # then decide from the settled membership.
    # A failed read keeps the last known state, so it never looks settled.
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
    if [ -z "$home" ]; then
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
    if [ "$writer" != "$home" ]; then
        mgmt_log "$id: writer is ${writer:-none}, switching it over to $home."
        export AURORA_GLOBAL_CLUSTER_ID="$id"
        # Right after a switchover, AWS refuses the next one while replication is
        # still being set up ("Please retry"). Retry that error only, until the
        # cluster deadline.
        while ! err=$(aws rds failover-global-cluster --global-cluster-identifier "$id" \
            --target-db-cluster-identifier "$home" --no-cli-pager 2>&1 >/dev/null) &&
            [[ "$err" == *"replication setup is still in progress"* ]] && [ "$SECONDS" -lt "$deadline" ]; do
            mgmt_log "$id: replication still setting up, retrying the switchover."
            sleep "${AURORA_WRITER_POLL_SECONDS:-15}"
        done
        [ -n "$err" ] && mgmt_err "$id: $err"
        if [ -n "$err" ] || ! aurora_wait_writer "$home" "$((deadline > SECONDS ? deadline - SECONDS : 1))"; then
            mgmt_err "$id: could not move the writer home, terraform destroy may hang."
            failed=true
            continue
        fi
    fi
    # A reader still attached makes AWS refuse to delete the writer's last
    # instance, and terraform retries that until its timeout. This happens when
    # an interrupted destroy dropped the reader from the state but not from
    # the global cluster. Detaching every reader first lets the destroy finish.
    for reader in $(echo "$global" | jq -r --arg h "$home" '.GlobalClusterMembers[].DBClusterArn | select(. != $h)'); do
        region=$(echo "$reader" | cut -d: -f4)
        name=$(echo "$reader" | cut -d: -f7)
        # A reader without instances cannot become a standalone cluster, so a
        # detach never settles (run 37809356148). Delete it instead: AWS lists
        # this as a normal step when deleting a global database.
        if ! members=$(aws rds describe-db-clusters --region "$region" --db-cluster-identifier "$name" \
            --query 'length(DBClusters[0].DBClusterMembers)' --output text); then
            mgmt_err "$id: could not read $reader, terraform destroy may hang."
            failed=true
        elif [ "$members" = 0 ]; then
            mgmt_log "$id: deleting reader $reader, which has no instance."
            if ! aws rds delete-db-cluster --region "$region" --db-cluster-identifier "$name" \
                --skip-final-snapshot --no-cli-pager >/dev/null ||
                ! aws rds wait db-cluster-deleted --region "$region" --db-cluster-identifier "$name"; then
                mgmt_err "$id: could not delete $reader, terraform destroy may hang."
                failed=true
            fi
        else
            mgmt_log "$id: detaching reader $reader."
            if ! aws rds remove-from-global-cluster --region "$region" --global-cluster-identifier "$id" \
                --db-cluster-identifier "$reader" --no-cli-pager >/dev/null ||
                ! aws rds wait db-cluster-available --region "$region" --db-cluster-identifier "$name"; then
                mgmt_err "$id: could not detach $reader, terraform destroy may hang."
                failed=true
            fi
        fi
    done
done < <(echo "$globals" | jq -c --arg m "$MATCH" --arg exact "${RESTORE_EXACT_ID:-false}" \
    '.[] | select(if $exact == "true" then .GlobalClusterIdentifier == $m
        else (.GlobalClusterIdentifier | test("^e2e-[a-z]+(-[a-z]+)*-[a-z0-9]+-global-db$")) and (.GlobalClusterIdentifier | test($m)) end)')
done_restoring
