#!/usr/bin/env bash
# Counting semaphore on S3 conditional writes, gated on free AWS quota.
#
#   slot.sh acquire   -> waits for free quota and a free slot, prints slot-key=<key>
#   slot.sh release   -> deletes SLOT_KEY if this run still owns it
#
# A slot is the object ci-locks/<POOL>/slot-<i>. It is created with
# If-None-Match: *, so only one writer wins. Its body holds the owner and a
# lease expiry; a run that died without releasing loses the slot once the lease
# expires, and the next run takes it over with If-Match on the old ETag. No
# daily reset is needed.
set -euo pipefail

: "${BUCKET:?}" "${BUCKET_REGION:?}" "${POOL:?}" "${OWNER:?}"
prefix="ci-locks/${POOL}"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

s3() { aws s3api "$@" --region "$BUCKET_REGION" --bucket "$BUCKET" --no-cli-pager; }

# Fails on any error other than a lost precondition, so a credentials or bucket
# problem stops the run instead of looking like a busy pool until the timeout.
conditional() {
    if "$@" >/dev/null 2>"$scratch/err"; then return 0; fi
    grep -qE 'PreconditionFailed|ConditionalRequestConflict' "$scratch/err" && return 1
    cat "$scratch/err" >&2
    exit 1
}

# Usage of one quota in one region. Resources still deleting count, as AWS
# counts them against the quota too.
usage() {
    local region=$2
    case "$1" in
    rds-clusters) aws rds describe-db-clusters --region "$region" --query 'length(DBClusters)' --output text ;;
    rds-instances) aws rds describe-db-instances --region "$region" --query 'length(DBInstances)' --output text ;;
    vpcs) aws ec2 describe-vpcs --region "$region" --query 'length(Vpcs)' --output text ;;
    elastic-ips) aws ec2 describe-addresses --region "$region" --query 'length(Addresses)' --output text ;;
    transit-gateways) aws ec2 describe-transit-gateways --region "$region" \
        --filters Name=state,Values=pending,available,modifying,deleting \
        --query 'length(TransitGateways)' --output text ;;
    albs) aws elbv2 describe-load-balancers --region "$region" \
        --query "length(LoadBalancers[?Type=='application'])" --output text ;;
    nlbs) aws elbv2 describe-load-balancers --region "$region" \
        --query "length(LoadBalancers[?Type=='network'])" --output text ;;
    esac
}

# Service code and quota code of each resource usage() knows.
quota_code() {
    case "$1" in
    rds-clusters) echo "rds L-952B80B8" ;;
    rds-instances) echo "rds L-7B6409FD" ;;
    vpcs) echo "vpc L-F678F1CE" ;;
    elastic-ips) echo "ec2 L-0263D0A3" ;;
    transit-gateways) echo "ec2 L-A2478D36" ;;
    albs) echo "elasticloadbalancing L-53DA6B97" ;;
    nlbs) echo "elasticloadbalancing L-69A177A2" ;;
    *) return 1 ;;
    esac
}

# NEEDS is one `<resource>=<count>` per line: what one run creates in each region.
# Unknown resources fail at once, so a typo does not silently skip the check.
for need in ${NEEDS:-}; do
    quota_code "${need%%=*}" >/dev/null || {
        echo "::error::Unknown resource '${need%%=*}' in needs." >&2
        exit 2
    }
done

# True when every region has room for everything this run needs.
# ponytail: not atomic with the slot; two runs can pass at once. The slot count
# bounds that, and the margin absorbs it.
room() {
    local region need resource count used quota ok=0
    for region in ${REGIONS:-}; do
        for need in ${NEEDS:-}; do
            resource=${need%%=*}
            count=${need#*=}
            used=$(usage "$resource" "$region")
            # shellcheck disable=SC2046 # "<service> <code>" splits into two arguments
            set -- $(quota_code "$resource")
            quota=$(aws service-quotas get-service-quota --region "$region" --service-code "$1" \
                --quota-code "$2" --query 'Quota.Value' --output text)
            quota=${quota%.*}
            if ((used + count + MARGIN > quota)); then
                echo "${region} ${resource}: ${used}/${quota} used, this run needs ${count} (+${MARGIN} margin)"
                ok=1
            fi
        done
    done
    return "$ok"
}

try_slot() {
    local key="$prefix/slot-$1" now etag
    now=$(date +%s)
    jq -nc --arg owner "$OWNER" --argjson expires $((now + LEASE_MINUTES * 60)) \
        '{owner: $owner, expires: $expires}' >"$scratch/body"

    slot_key=$key
    if conditional s3 put-object --key "$key" --body "$scratch/body" --if-none-match '*'; then
        return 0
    fi

    # Taken. Reclaim it if the lease expired or this run already holds it (step retry).
    etag=$(s3 get-object --key "$key" "$scratch/current" --query ETag --output text 2>/dev/null) || return 1
    if [[ "$(jq -r .owner "$scratch/current")" != "$OWNER" ]] &&
        (($(jq -r .expires "$scratch/current") > now)); then
        return 1
    fi
    conditional s3 put-object --key "$key" --body "$scratch/body" --if-match "$etag"
}

acquire() {
    local deadline i
    deadline=$(($(date +%s) + WAIT_MINUTES * 60))
    while :; do
        if room; then
            for ((i = 0; i < SLOTS; i++)); do
                if try_slot "$i"; then
                    echo "Acquired ${slot_key} for ${OWNER}"
                    echo "slot-key=${slot_key}" >>"${GITHUB_OUTPUT:-/dev/null}"
                    return 0
                fi
            done
            echo "All ${SLOTS} slots of ${POOL} are busy:"
            for ((i = 0; i < SLOTS; i++)); do
                s3 get-object --key "$prefix/slot-$i" "$scratch/current" >/dev/null 2>&1 &&
                    echo "  slot-$i: $(jq -c . "$scratch/current")"
            done
        fi
        if (($(date +%s) >= deadline)); then
            echo "::error::No capacity in pool ${POOL} after ${WAIT_MINUTES} minutes."
            return 1
        fi
        sleep "${POLL_SECONDS:-60}"
    done
}

release() {
    local etag
    [[ -n "${SLOT_KEY:-}" ]] || {
        echo "No slot to release."
        return 0
    }
    etag=$(s3 get-object --key "$SLOT_KEY" "$scratch/current" --query ETag --output text 2>/dev/null) || {
        echo "${SLOT_KEY} is already gone."
        return 0
    }
    if [[ "$(jq -r .owner "$scratch/current")" != "$OWNER" ]]; then
        echo "::warning::${SLOT_KEY} now belongs to $(jq -r .owner "$scratch/current"), leaving it."
        return 0
    fi
    conditional s3 delete-object --key "$SLOT_KEY" --if-match "$etag" ||
        echo "::warning::${SLOT_KEY} changed while releasing, leaving it."
    echo "Released ${SLOT_KEY}"
}

case "${1:-}" in
acquire | release) "$1" ;;
*)
    echo "usage: $0 acquire|release" >&2
    exit 2
    ;;
esac
