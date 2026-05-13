#!/bin/bash
# Sweep orphan ELBv2 target groups in a region.
#
# A target group is "orphan" when it is not attached to any load balancer.
# AWS does not cascade-delete target groups when their parent load balancer
# is removed, so they accumulate until they exhaust the per-region quota
# (TooManyTargetGroups). cloud-nuke does not natively support standalone
# ELBv2 target groups (only the LBs themselves), so this script does the
# sweep directly via the AWS CLI.
#
# Race-safety:
#   AWS does not expose a creation time on target groups via DescribeTargetGroups,
#   so we cannot filter by age. Instead, a TG is only deleted if it appears as
#   orphan in TWO snapshots taken SETTLE_SECONDS apart. A TG that is mid-attach
#   (created but not yet wired to an LB by Terraform / ingress controller / AWS
#   Load Balancer Controller) will gain a LoadBalancerArns entry inside the wait
#   window and drop out of the second snapshot, so we will not delete it.
#
# Other safety:
#   - If AWS rejects a delete (e.g. a listener rule still references it), the
#     error is logged but does not abort the script.
#   - DRY_RUN=true logs candidates and exits without deleting.
#
# Usage:
#   ./nuke-orphan-target-groups.sh <region>
#
# Arguments:
#   region  AWS region to sweep (e.g. eu-west-2).
#
# Environment:
#   DRY_RUN         If "true", list candidates and exit without deleting.
#   SETTLE_SECONDS  Seconds to wait between the two orphan snapshots.
#                   Defaults to 120 (covers typical Terraform/ingress LB
#                   provisioning windows of 2–3 minutes).

set -euo pipefail

REGION="${1:?region required (e.g. eu-west-2)}"
DRY_RUN="${DRY_RUN:-false}"
SETTLE_SECONDS="${SETTLE_SECONDS:-120}"

list_orphans() {
    aws elbv2 describe-target-groups \
        --region "$REGION" \
        --query "TargetGroups[?length(LoadBalancerArns)==\`0\`].TargetGroupArn" \
        --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' || true
}

echo "Listing ELBv2 target groups in ${REGION} (pass 1)..."
mapfile -t pass1 < <(list_orphans)
pass1_count=${#pass1[@]}
echo "Pass 1: ${pass1_count} orphan target group(s)."

if [[ $pass1_count -eq 0 ]]; then
    exit 0
fi

echo "Waiting ${SETTLE_SECONDS}s before re-checking to avoid deleting TGs mid-attach..."
sleep "$SETTLE_SECONDS"

echo "Listing ELBv2 target groups in ${REGION} (pass 2)..."
mapfile -t pass2 < <(list_orphans)
declare -A still_orphan=()
for arn in "${pass2[@]}"; do
    still_orphan["$arn"]=1
done

confirmed=()
for arn in "${pass1[@]}"; do
    if [[ -n "${still_orphan[$arn]:-}" ]]; then
        confirmed+=("$arn")
    else
        echo "Skipping ${arn} — attached to an LB during the settle window."
    fi
done

total=${#confirmed[@]}
echo "Confirmed orphan target group(s) in ${REGION}: ${total}"

if [[ $total -eq 0 ]]; then
    exit 0
fi

deleted=0
skipped=0
for tg_arn in "${confirmed[@]}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would delete: $tg_arn"
        continue
    fi
    if aws elbv2 delete-target-group \
            --target-group-arn "$tg_arn" \
            --region "$REGION" 2>/tmp/tg-delete-err; then
        echo "Deleted: $tg_arn"
        deleted=$((deleted + 1))
    else
        echo "Skipped (delete failed): $tg_arn — $(cat /tmp/tg-delete-err)"
        skipped=$((skipped + 1))
    fi
done

echo "Done in ${REGION}: deleted=${deleted}, skipped=${skipped}, total=${total}"
