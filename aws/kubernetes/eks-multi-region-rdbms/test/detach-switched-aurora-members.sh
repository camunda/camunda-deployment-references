#!/usr/bin/env bash
# Prepares a switched-over Aurora Global Database for `terraform destroy`.
#
# Terraform creates the writer in region slot 0. A failover test moves it to
# another region, and when failback does not run, the writer is still there at
# teardown. Terraform then deletes the instances before the clusters and fails on
# the writer's last one, for two hours per destroy pass:
#
#   InvalidDBClusterStateFault: Cannot delete the last instance of the master
#   cluster. Delete the replica cluster before deleting the last master cluster
#   instance.
#
# Detaching the reader members removes that blocker, so the destroy that follows
# runs as usual. A detach needs no switchover, unlike moving the writer home, so
# it also works when region slot 0 is degraded.
#
# Usage: detach-switched-aurora-members.sh <id-regex> <min-age-hours>
#   <id-regex>       only global clusters whose identifier matches it (jq regex).
#                    Identifiers must also end in -global-db, the naming of
#                    terraform/clusters/database.tf.
#   <min-age-hours>  skip a global cluster whose Terraform state is younger. This
#                    is the gate the destroy applies (destroy-resources.sh), read
#                    from the same object, s3://$STATE_BUCKET/${STATE_PREFIX}
#                    tfstate-<cluster-name>/clusters.tfstate. So the sweep never
#                    detaches a stack the destroy then skips. 0 skips the lookup.
# Env: TF_VAR_region_0 (region slot 0), STATE_BUCKET, STATE_BUCKET_REGION and
#      STATE_PREFIX when <min-age-hours> is above 0, AURORA_SETTLE_SECONDS
#      (default 1200) to wait for a running switchover, AURORA_POLL_SECONDS
#      (default 15).
#
# Best effort: a failure is logged and the next cluster is tried, so the
# Terraform destroy that follows always runs.
set -uo pipefail

MATCH="${1:?identifier regex required}"
MIN_AGE_HOURS="${2:?minimum age in hours required}"
: "${TF_VAR_region_0:?TF_VAR_region_0 must be set to region slot 0}"

# A dispatch input is free text. Anything other than a whole number would make the
# age test below error out, read as false, and skip the gate the destroy applies.
# Four digits at most: a longer one overflows Bash arithmetic and wraps around.
if ! [[ "$MIN_AGE_HOURS" =~ ^[0-9]{1,4}$ ]]; then
    echo "[detach-switched-aurora] <min-age-hours> must be a whole number of at most 4 digits, got '$MIN_AGE_HOURS'; detaching nothing." >&2
    exit 0
fi

log() { echo "[detach-switched-aurora] $*" >&2; }
region_of() { cut -d: -f4 <<<"$1"; }
name_of() { cut -d: -f7 <<<"$1"; }

if ! globals=$(aws rds describe-global-clusters --query 'GlobalClusters' --output json); then
    log "could not list the Aurora global clusters, terraform destroy may fail on a switched writer."
    exit 0
fi

now=$(date -u +%s)
jq -c --arg m "$MATCH" '.[] | select((.GlobalClusterIdentifier | test($m)) and (.GlobalClusterIdentifier | endswith("-global-db")))' \
    <<<"$globals" | while read -r global; do
    id=$(jq -r .GlobalClusterIdentifier <<<"$global")

    # A running switchover shows the old writer flag, and a detach is refused
    # while it lasts. Decide from the settled membership.
    deadline=$((SECONDS + ${AURORA_SETTLE_SECONDS:-1200}))
    while [ -n "$(jq -r '.FailoverState.Status // ""' <<<"$global")" ] && [ "$SECONDS" -lt "$deadline" ]; do
        log "$id: switchover in progress, waiting."
        sleep "${AURORA_POLL_SECONDS:-15}"
        global=$(aws rds describe-global-clusters --global-cluster-identifier "$id" \
            --query 'GlobalClusters[0]' --output json) || true
    done

    writer=$(jq -r '[.GlobalClusterMembers[] | select(.IsWriter)][0].DBClusterArn // ""' <<<"$global")
    if [ -z "$writer" ]; then
        log "$id: no writer member, nothing to do."
        continue
    fi
    if [ "$(region_of "$writer")" = "$TF_VAR_region_0" ]; then
        log "$id: writer is in region slot 0 ($TF_VAR_region_0), terraform destroy handles it."
        continue
    fi

    if [ "$MIN_AGE_HOURS" -gt 0 ]; then
        key="${STATE_PREFIX:?STATE_PREFIX must be set when <min-age-hours> is above 0}tfstate-${id%-global-db}/clusters.tfstate"
        modified=$(aws s3api head-object --region "${STATE_BUCKET_REGION:?}" --bucket "${STATE_BUCKET:?}" \
            --key "$key" --query LastModified --output text 2>/dev/null) || modified=""
        # S3 answers e.g. 2026-10-06T20:41:37+00:00. jq parses it the same way on
        # GNU and BSD userlands, unlike `date -d`.
        modified_epoch=$(jq -rn --arg t "$modified" '$t | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601' 2>/dev/null) || {
            log "$id: no readable state at s3://$STATE_BUCKET/$key, the destroy skips it too, skipping."
            continue
        }
        # One hour earlier than the destroy's cutoff. The destroy reads its clock
        # later, after this step (30 min at most) and its own setup, so a state
        # crossing the line in between would otherwise be destroyed unprepared.
        # Preparing a stack the destroy then skips is harmless: it is at least
        # MIN_AGE_HOURS - 1 old, far past any running test, and its detached
        # readers are standalone clusters the next sweep removes.
        age_minutes=$(((now - modified_epoch) / 60))
        if [ "$age_minutes" -lt $((MIN_AGE_HOURS * 60 - 60)) ]; then
            log "$id: state $((age_minutes / 60))h old, younger than ${MIN_AGE_HOURS}h minus the 1h margin, skipping."
            continue
        fi
    fi

    log "$id: writer moved to $(region_of "$writer"), detaching the reader members."
    for reader in $(jq -r '.GlobalClusterMembers[] | select(.IsWriter | not) | .DBClusterArn' <<<"$global"); do
        region=$(region_of "$reader")
        if aws rds remove-from-global-cluster --region "$region" \
            --global-cluster-identifier "$id" --db-cluster-identifier "$reader" >/dev/null; then
            # A detached member is `modifying` for about a minute, and terraform
            # cannot delete its instances until it is available again.
            aws rds wait db-cluster-available --region "$region" \
                --db-cluster-identifier "$(name_of "$reader")" ||
                log "$id: $(name_of "$reader") did not become available, the destroy may retry."
            log "$id: detached $(name_of "$reader")."
        else
            log "$id: could not detach $(name_of "$reader")."
        fi
    done
done
exit 0
