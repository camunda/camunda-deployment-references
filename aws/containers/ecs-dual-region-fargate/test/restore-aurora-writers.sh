#!/usr/bin/env bash
# Prepares the Aurora global cluster of leftover ECS dual-region test stacks
# for terraform destroy: moves a writer that a failover test moved away back to
# region 0 (see the README teardown section), then detaches the readers, so the
# destroy cannot hang on the writer's last instance. The workflow cleanup and
# the daily cleanup run it before the Terraform destroy.
#
# Usage: restore-aurora-writers.sh <id-regex> <min-age-hours>
#   <id-regex>       only global clusters whose identifier matches it (jq
#                    regex). Identifiers must also follow a test naming, so
#                    no other stack is ever touched: the Terratest suites'
#                    ^e2e-<label>-<suffix>-global-db$, or the failover
#                    lifecycle lane's ^ecsdr-<pr|sha>-global-db$. With RESTORE_EXACT_ID=true (the Go
#                    test cleanup), <id-regex> is instead the exact identifier
#                    of one global cluster, whatever its naming.
#   <min-age-hours>  skip stacks whose newest app or infra state is younger
#                    than this, in whole hours as the destroy counts them
# Env: REGION_0 (home region), AWS_PROFILE / AWS_REGION as for the AWS CLI,
#      STATE_BUCKET, STATE_BUCKET_REGION and STATE_PREFIX, required when
#      <min-age-hours> is above 0. Whenever STATE_PREFIX is set, a stack is
#      only touched if it has an app or infra state under that prefix, whatever
#      the age, so a sweep never reaches another branch's stacks. The age is
#      the newest LastModified of the stack's
#      ${STATE_PREFIX}tfstate-<cluster>[-run<id>]/{app,infra}/terraform.tfstate
#      objects. The destroy handles app before infra and stops the stack at
#      the first fresh one, so a fresh app state skips an old infra state.
#      AURORA_SETTLE_SECONDS (default 1200): the whole budget of one cluster,
#      passed to aurora_switch_to (procedure/aurora.sh), which shares it
#      between settling a running switchover, retrying while replication sets
#      up, and waiting for the move home.
#      RESTORE_BUDGET_SECONDS (default unlimited): the budget of the whole run.
#      A cluster is only started if a full per-cluster budget still fits, so
#      a step timeout set above it never kills a switchover midway.
#
# Best effort: a failure is logged and the next cluster is tried, so the
# Terraform destroy that follows always runs. The one exception to exiting 0
# is a state listing that errors under STATE_PREFIX, which always exits 1:
# it means the sweep cannot tell which stacks it owns. With RESTORE_STRICT=true (the Go
# test cleanup), the script still tries every cluster but exits 1 if any
# writer could not be checked or moved home.
set -uo pipefail

MATCH="${1:?identifier regex required}"
MIN_AGE_HOURS="${2:?minimum age in hours required}"
: "${REGION_0:?REGION_0 must be set}"

# shellcheck source=aws/containers/ecs-dual-region-fargate/procedure/zeebe_management_api.sh
. "$(dirname "$0")/../procedure/zeebe_management_api.sh"
# shellcheck source=aws/containers/ecs-dual-region-fargate/procedure/aurora.sh
. "$(dirname "$0")/../procedure/aurora.sh"

now=$(date -u +%s)
failed=false
# A state listing that errors is a configuration fault, not a per-cluster
# hiccup: the wrong bucket, prefix or credentials make every stack look
# unowned, so the sweep would skip everything and still report success. It
# fails the run even outside strict mode. The destroy that follows still
# runs: both daily-cleanup Delete steps are `if: always()`.
state_unreadable=false
done_restoring() {
    [ "$state_unreadable" = true ] && exit 1
    [ "${RESTORE_STRICT:-false}" = true ] && [ "$failed" = true ] && exit 1
    exit 0
}
# A malformed value would make the age test error out and skip the age gate.
if ! [[ "$MIN_AGE_HOURS" =~ ^[0-9]{1,4}$ ]]; then
    mgmt_err "minimum age '$MIN_AGE_HOURS' is not a whole number of hours (0-9999), restoring nothing."
    failed=true
    done_restoring
fi
# The age is read from the state objects, so it needs their location.
if [ "$MIN_AGE_HOURS" -gt 0 ]; then
    : "${STATE_BUCKET:?STATE_BUCKET must be set when <min-age-hours> is above 0}"
    : "${STATE_BUCKET_REGION:?STATE_BUCKET_REGION must be set when <min-age-hours> is above 0}"
    : "${STATE_PREFIX:?STATE_PREFIX must be set when <min-age-hours> is above 0}"
fi
if ! globals=$(aws rds describe-global-clusters --query 'GlobalClusters' --output json); then
    mgmt_err "could not list the Aurora global clusters, terraform destroy may hang."
    failed=true
    done_restoring
fi
cluster_budget=${AURORA_SETTLE_SECONDS:-1200}
while read -r global; do
    id=$(echo "$global" | jq -r .GlobalClusterIdentifier)
    # Decide eligibility first: a young stack must not spend the run budget
    # settling a switchover that the destroy will not act on anyway.
    # A prefix-scoped sweep only owns the stacks whose states live under its
    # STATE_PREFIX, at any age: the identifier filter separates suites, not
    # branches, and main and stable branches both run ecsdr-<pr> lanes. With a
    # zero age this gate used to be skipped altogether, so a manual sweep could
    # move the writer of another branch's live deployment.
    if [ -n "${STATE_PREFIX:-}" ]; then
        # Once a listing has failed, the rest would fail the same way: skip
        # them without another S3 call, but still name each one in the log.
        if [ "$state_unreadable" = true ]; then
            mgmt_log "$id: the states are unreadable, so its ownership is unknown, skipping."
            continue
        fi
        # Gate on the state objects the destroy gates on, not on the cluster's
        # age. The destroy handles app before infra and stops the whole stack
        # at the first fresh one, so the newest of the two decides.
        cluster=${id%-global-db}
        list_args=(s3api list-objects-v2 --region "${STATE_BUCKET_REGION:?}" --bucket "${STATE_BUCKET:?}"
            --prefix "${STATE_PREFIX:?}tfstate-$cluster" --output json)
        # The exit status is what separates "no state here" from "could not
        # look": an access error, a wrong bucket or region all used to land on
        # the "not this sweep's" skip below and keep a misconfigured cleanup
        # green. Only stdout is captured, so jq still gets pure JSON, and the
        # AWS error of this very request lands in the log, just above.
        if ! listing=$(aws "${list_args[@]}"); then
            mgmt_err "$id: could not list s3://${STATE_BUCKET}/${STATE_PREFIX}tfstate-$cluster (AWS error above), so its ownership is unknown."
            echo "::error::restore-aurora-writers: cannot read the Terraform states under s3://${STATE_BUCKET}/${STATE_PREFIX}; check the bucket, region, prefix and credentials, or re-run if S3 failed transiently (throttling, 5xx)"
            failed=true
            state_unreadable=true
            continue
        fi
        modified=$(echo "$listing" |
            jq -r --arg re "/tfstate-$cluster(-run[0-9]+)?/(app|infra)/terraform[.]tfstate$" \
            '[.Contents[]? | select(.Key | test($re)) | .LastModified] | max // empty')
        if ! modified_s=$(jq -rn --arg t "$modified" '$t | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601' 2>/dev/null); then
            mgmt_log "$id: no readable app or infra state under ${STATE_PREFIX}, not this sweep's to touch, skipping."
            continue
        fi
        # Whole hours, as the destroy counts them.
        if [ "$MIN_AGE_HOURS" -gt 0 ] && [ $(((now - modified_s) / 3600)) -lt "$MIN_AGE_HOURS" ]; then
            mgmt_log "$id: state younger than ${MIN_AGE_HOURS}h, skipping."
            continue
        fi
    fi
    if [ -n "${RESTORE_BUDGET_SECONDS:-}" ] && [ $((SECONDS + cluster_budget)) -gt "$RESTORE_BUDGET_SECONDS" ]; then
        mgmt_err "$id: not enough run budget left for another cluster, skipping it. terraform destroy may hang."
        failed=true
        continue
    fi
    home=$(echo "$global" | jq -r --arg r "$REGION_0" \
        '[.GlobalClusterMembers[] | select((.DBClusterArn | split(":")[3]) == $r)][0].DBClusterArn // empty')
    if [ -z "$home" ]; then
        mgmt_err "$id: no member in $REGION_0 to move the writer to, terraform destroy may hang."
        failed=true
        continue
    fi
    # The listing is enough when it shows a settled writer at home. Otherwise
    # aurora_switch_to lets a running switchover settle and moves the writer.
    writer=$(echo "$global" | jq -r '.GlobalClusterMembers[] | select(.IsWriter) | .DBClusterArn')
    if [ -n "$(echo "$global" | jq -r '.FailoverState.Status // ""')" ] || [ "$writer" != "$home" ]; then
        mgmt_log "$id: writer is ${writer:-none}, making $home the writer."
        export AURORA_GLOBAL_CLUSTER_ID="$id"
        if ! aurora_switch_to "$home" "$cluster_budget"; then
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
        # A reader without instances can be neither detached (it never settles,
        # run 37809356148) nor deleted while it is a member (AWS refuses,
        # run 37912265264). Report it at once instead of waiting 30 minutes.
        if ! members=$(aws rds describe-db-clusters --region "$region" --db-cluster-identifier "$name" \
            --query 'length(DBClusters[0].DBClusterMembers)' --output text); then
            mgmt_err "$id: could not read $reader, terraform destroy may hang."
            failed=true
        elif [ "$members" = 0 ]; then
            mgmt_err "$id: reader $reader has no instance and cannot be detached or deleted. Add an instance to it, detach it, then delete it; terraform destroy will hang until then."
            failed=true
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
        else (.GlobalClusterIdentifier | test("^(e2e-[a-z]+(-[a-z]+)*|ecsdr)-[a-z0-9]+-global-db$")) and (.GlobalClusterIdentifier | test($m)) end)')
done_restoring
