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
#   <min-age-hours>  skip global clusters whose writer is younger, so the daily
#                    sweep never touches a test that is still running.
# Env: TF_VAR_region_0 (region slot 0), AURORA_SETTLE_SECONDS (default 1200) to
#      wait for a running switchover, AURORA_POLL_SECONDS (default 15).
#
# Best effort: a failure is logged and the next cluster is tried, so the
# Terraform destroy that follows always runs.
set -uo pipefail

MATCH="${1:?identifier regex required}"
MIN_AGE_HOURS="${2:?minimum age in hours required}"
: "${TF_VAR_region_0:?TF_VAR_region_0 must be set to region slot 0}"

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

    created=$(aws rds describe-db-clusters --region "$(region_of "$writer")" \
        --db-cluster-identifier "$(name_of "$writer")" \
        --query 'DBClusters[0].ClusterCreateTime' --output text 2>/dev/null) || created=""
    if [ -z "$created" ] || [ "$created" = None ]; then
        log "$id: could not read the writer's age, skipping."
        continue
    fi
    # AWS answers e.g. 2026-10-06T15:52:10.123000+00:00. jq parses it the same way
    # on GNU and BSD userlands, unlike `date -d`.
    created_epoch=$(jq -rn --arg t "$created" '$t | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601') || {
        log "$id: unreadable writer creation time '$created', skipping."
        continue
    }
    age_hours=$(((now - created_epoch) / 3600))
    if [ "$age_hours" -lt "$MIN_AGE_HOURS" ]; then
        log "$id: ${age_hours}h old, younger than ${MIN_AGE_HOURS}h, skipping."
        continue
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
