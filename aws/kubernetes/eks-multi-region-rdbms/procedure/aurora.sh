#!/usr/bin/env bash
# Aurora Global Database switchover helpers. Source this file, do not run it.
#
# The ECS dual-region and EKS multi-region references each carry a copy, so
# each reference stays self-contained. Keep the two copies identical; an
# offline test compares them:
#   aws/containers/ecs-dual-region-fargate/procedure/aurora.sh
#   aws/kubernetes/eks-multi-region-rdbms/procedure/aurora.sh
#
# Every function needs AURORA_GLOBAL_CLUSTER_ID, logs to stderr, and sends each
# AWS call to an explicit region: the CLI default region can be the lost one.

# aurora_settled_global <api-region> [timeout]
#
# Prints the GlobalClusters[0] object once no switchover runs. Early in a
# switchover the old writer still has IsWriter set, so a caller that decides
# from a running switchover starts a second one, which AWS rejects. Returns 1
# when the read fails or the timeout ends.
aurora_settled_global() {
    local region=$1 max_wait=${2:-900} global_json state
    local deadline=$((SECONDS + max_wait))
    while true; do
        global_json=$(aws rds describe-global-clusters \
            --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
            --query 'GlobalClusters[0]' --output json --region "${region}") || return 1
        state=$(echo "${global_json}" | jq -r '.FailoverState.Status // ""')
        [ -z "${state}" ] && { echo "${global_json}"; return 0; }
        if [ "${SECONDS}" -ge "${deadline}" ]; then
            echo "ERROR: a switchover of ${AURORA_GLOBAL_CLUSTER_ID} is still ${state} after ${max_wait}s." >&2
            return 1
        fi
        echo "    A switchover is ${state}, waiting for it to settle." >&2
        sleep "${AURORA_WRITER_POLL_SECONDS:-15}"
    done
}

# aurora_wait_writer <target-cluster-arn> [timeout]
#
# failover-global-cluster returns while the switchover is still pending, and
# the target cluster reports "available" before the writer moves. Poll the
# global cluster until the target is the writer and no FailoverState is left.
# A failed read counts as "not done yet".
aurora_wait_writer() {
    local target_arn=$1 max_wait=${2:-900} region global_json writer state
    [ -n "${target_arn}" ] || { echo "ERROR: no target writer ARN" >&2; return 1; }
    region=$(echo "${target_arn}" | cut -d: -f4)
    local deadline=$((SECONDS + max_wait))
    while true; do
        global_json=$(aws rds describe-global-clusters \
            --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
            --query 'GlobalClusters[0]' --output json --region "${region}" 2>/dev/null) || global_json='{}'
        writer=$(echo "${global_json}" | jq -r '.GlobalClusterMembers[]? | select(.IsWriter == true) | .DBClusterArn')
        state=$(echo "${global_json}" | jq -r '.FailoverState.Status // ""')
        if [ "${writer}" = "${target_arn}" ] && [ -z "${state}" ]; then
            echo "    The Aurora switchover finished." >&2
            return 0
        fi
        if [ "${SECONDS}" -ge "${deadline}" ]; then
            echo "ERROR: the Aurora switchover to ${target_arn} did not finish within ${max_wait}s" \
                "(writer: ${writer:-none}, failover state: ${state:-none})." >&2
            return 1
        fi
        echo "    Waiting for the Aurora switchover (writer: ${writer:-none}, state: ${state:-none})." >&2
        sleep "${AURORA_WRITER_POLL_SECONDS:-15}"
    done
}

# aurora_switch_to <target-cluster-arn> [timeout]
#
# Makes the target the writer, and is safe to rerun: it lets a running
# switchover settle, does nothing when the target is already the writer, and
# otherwise runs a planned switchover and waits until it finished. The timeout
# covers all of it.
aurora_switch_to() {
    local target_arn=$1 max_wait=${2:-900} region global_json writer out
    [ -n "${target_arn}" ] || { echo "ERROR: no target writer ARN" >&2; return 1; }
    region=$(echo "${target_arn}" | cut -d: -f4)
    local deadline=$((SECONDS + max_wait))

    global_json=$(aurora_settled_global "${region}" "${max_wait}") || return 1
    writer=$(echo "${global_json}" | jq -r '.GlobalClusterMembers[] | select(.IsWriter == true) | .DBClusterArn')
    if [ "${writer}" = "${target_arn}" ]; then
        echo "    The Aurora writer is already ${target_arn}." >&2
        return 0
    fi

    # Settling may have used the whole budget: never start a switchover that

    # could not be awaited, it would keep running after this returns an error.

    if [ "${SECONDS}" -ge "${deadline}" ]; then

        echo "ERROR: no time left to switch the Aurora writer to ${target_arn}." >&2

        return 1

    fi

    echo "    Planned switchover from ${writer:-none} to ${target_arn}." >&2
    # Right after a switchover, AWS refuses the next one while replication is
    # still being set up ("Please retry"). Retry that error only.
    while ! out=$(aws rds failover-global-cluster \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --target-db-cluster-identifier "${target_arn}" \
        --region "${region}" --no-cli-pager 2>&1 >/dev/null); do
        if [[ "${out}" != *"replication setup is still in progress"* ]] || [ "${SECONDS}" -ge "${deadline}" ]; then
            echo "ERROR: ${out}" >&2
            return 1
        fi
        echo "    Replication is still being set up, retrying the switchover." >&2
        sleep "${AURORA_WRITER_POLL_SECONDS:-15}"
    done
    aurora_wait_writer "${target_arn}" "$((deadline > SECONDS ? deadline - SECONDS : 0))"
}
