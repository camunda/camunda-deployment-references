#!/bin/bash
set -euo pipefail

# Switches the AWS VPC CNI to custom networking, so that pods are addressed out
# of the VPC secondary CIDR created by terraform/clusters/pod-networking.tf
# instead of the routed node subnets.
#
#   ./configure-vpc-cni-custom-networking.sh [slot]
#
# WHY THIS EXISTS
#
# With the stock VPC CNI a pod address IS a VPC address. Submariner installs
# node routes for every remote cluster CIDR it is joined with, so those routes
# then also cover the remote NODES — including the gateway addresses its own
# tunnels are built on — while the Transit Gateway still advertises the same
# prefix. Peers resolve, packets never arrive, and Zeebe never forms a Raft
# quorum. Moving pods into a range that no Transit Gateway route table carries
# breaks that circularity. See ../README.md, section "Pod networking".
#
# WHAT IT DOES, per active region:
#   1. turns on custom networking in the aws-node DaemonSet, tells it to pick an
#      ENIConfig by availability zone label, and excludes the remote pod and
#      service ranges from source NAT so a cross-region packet keeps the pod
#      address Submariner and the security groups are written for
#   2. creates one ENIConfig per zone, named after the zone so the label
#      resolves it, pointing at that zone's pod subnet and at the EKS cluster
#      security group
#   3. recycles the nodes, because custom networking only governs network
#      interfaces attached after it is enabled
#
# Run it BEFORE labelling the Submariner gateways: step 3 replaces every node
# and would otherwise discard the labels. It is idempotent: step 3 is skipped
# once every node already holds an interface in the pod subnets, which also
# makes it cheap to re-run over the whole cluster when a region is added and
# every other region's exclusion list has to learn the new ranges.
#
# CAVEAT 1 — step 3 TERMINATES every node of the region at once. That is
# deliberate: it runs at bootstrap, before any workload exists, and it is far
# faster than a one-at-a-time rollout. Pass a single slot when growing an
# existing deployment (../activate-region.sh does), and on a cluster that
# already carries traffic prefer
# `aws eks update-nodegroup-version --force` instead.
#
# CAVEAT 2 — the two settings in step 1 are written onto a DaemonSet owned by
# the EKS `vpc-cni` addon, which the Terraform module installs with
# `resolve_conflicts_on_update = OVERWRITE`. An addon upgrade therefore reverts
# them, and pods scheduled afterwards go back to the routed node range. Re-run
# this procedure after any addon upgrade; a production deployment should instead
# pin the values in the addon's `configuration_values`.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${AWS_REGIONS:?AWS_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${EKS_CLUSTER_NAMES:?EKS_CLUSTER_NAMES must be set, source export-terraform-outputs.sh}"
: "${REGION_POD_CIDRS:?REGION_POD_CIDRS must be set, source export-terraform-outputs.sh}"
: "${REGION_SERVICE_CIDRS:?REGION_SERVICE_CIDRS must be set, source export-terraform-outputs.sh}"

NODE_ROLL_TIMEOUT_SECONDS="${NODE_ROLL_TIMEOUT_SECONDS:-900}"
NODE_ROLL_POLL_INTERVAL_SECONDS="${NODE_ROLL_POLL_INTERVAL_SECONDS:-20}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
read -r -a aws_regions <<<"$AWS_REGIONS"
read -r -a cluster_names <<<"$EKS_CLUSTER_NAMES"
read -r -a pod_cidrs <<<"$REGION_POD_CIDRS"
read -r -a service_cidrs <<<"$REGION_SERVICE_CIDRS"

# CIDRs of every OTHER region, i.e. everything that must reach its destination
# through the Submariner tunnel with the source address intact.
remote_tunnel_cidrs() {
    local slot="$1" out=""

    for ((j = 0; j < CAMUNDA_ACTIVE_REGIONS; j++)); do
        [ "$j" -eq "$slot" ] && continue
        out="${out:+$out,}${pod_cidrs[$j]},${service_cidrs[$j]}"
    done
    echo "$out"
}

# Instance IDs of the nodes currently backing the cluster.
node_instance_ids() {
    local region="$1" cluster="$2"

    aws ec2 describe-instances --region "$region" \
        --filters "Name=tag:eks:cluster-name,Values=$cluster" \
        "Name=instance-state-name,Values=pending,running" \
        --query 'Reservations[].Instances[].InstanceId' --output text |
        tr '\t' '\n' | sed '/^$/d' | sort
}

# Instance IDs that already own a network interface in the pod subnets, i.e.
# the nodes on which custom networking has taken effect.
custom_networking_instance_ids() {
    local region="$1" subnet_csv="$2"

    aws ec2 describe-network-interfaces --region "$region" \
        --filters "Name=subnet-id,Values=$subnet_csv" \
        --query 'NetworkInterfaces[].Attachment.InstanceId' --output text |
        tr '\t' '\n' | sed '/^$/d; /^None$/d' | sort -u
}

configure_slot() {
    local slot="$1"
    local context="${contexts[$slot]}"
    local region="${aws_regions[$slot]}"
    local cluster="${cluster_names[$slot]}"

    echo "==> Region slot $slot: $cluster ($region)"

    local cluster_json vpc_id security_group_id
    cluster_json="$(aws eks describe-cluster --region "$region" --name "$cluster" \
        --query 'cluster.resourcesVpcConfig' --output json)"
    vpc_id="$(echo "$cluster_json" | jq -r '.vpcId')"
    # The EKS-managed cluster security group. Node instances already carry it,
    # and terraform/clusters/security.tf hangs the cross-region rules off it, so
    # reusing it for the pod interfaces is what makes a remote broker reachable.
    security_group_id="$(echo "$cluster_json" | jq -r '.clusterSecurityGroupId')"

    echo "    VPC $vpc_id, cluster security group $security_group_id"

    # The pod subnets are discovered by tag rather than passed in: they are a
    # (region, zone) matrix, which a space-separated environment variable cannot
    # express. pod-networking.tf owns the tag.
    local subnets
    subnets="$(aws ec2 describe-subnets --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:kubernetes.io/role/cni,Values=1" \
        --query 'sort_by(Subnets, &AvailabilityZone)[].[AvailabilityZone,SubnetId]' \
        --output text)"

    if [ -z "$subnets" ]; then
        echo "ERROR: no subnet tagged kubernetes.io/role/cni in $vpc_id." >&2
        echo "       Apply terraform/clusters first; the pod subnets come from pod-networking.tf." >&2
        return 1
    fi

    # AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS is as load-bearing as custom networking
    # itself. The CNI source-NATs every packet leaving the VPC to the node
    # address, and a remote pod range is by construction outside this VPC. The
    # remote cluster would then see a Zeebe connection arriving from a NODE
    # address while Submariner routes, and terraform/clusters/security.tf
    # authorises, POD addresses -- so the packets are dropped and Raft never
    # forms, with the tunnels reported healthy throughout.
    #
    # Submariner without Globalnet identifies a cluster by its pod CIDR, so
    # preserving the source address is not an optimisation, it is the model.
    local exclude_cidrs
    exclude_cidrs="$(remote_tunnel_cidrs "$slot")"
    echo "    Excluding from source NAT: $exclude_cidrs"

    echo "    Enabling custom networking in the aws-node DaemonSet"
    kubectl --context "$context" -n kube-system set env daemonset aws-node \
        AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true \
        ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone \
        AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS="$exclude_cidrs"

    # One ENIConfig per zone, named after the zone: ENI_CONFIG_LABEL_DEF makes
    # the CNI look up the ENIConfig whose name equals the node's zone label, so
    # a node only ever attaches interfaces in its own zone. A mismatch here
    # shows up as pods stuck in ContainerCreating, not as an explicit error.
    local subnet_csv=""
    while read -r zone subnet_id; do
        [ -n "$zone" ] || continue
        subnet_csv="${subnet_csv:+$subnet_csv,}$subnet_id"

        echo "    ENIConfig $zone -> $subnet_id"
        kubectl --context "$context" apply -f - <<EOF
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ${zone}
spec:
  subnet: ${subnet_id}
  securityGroups:
    - ${security_group_id}
EOF
    done <<<"$subnets"

    roll_nodes "$context" "$region" "$cluster" "$subnet_csv"
}

# Recycles the nodes so that they attach their pod interfaces in the pod
# subnets. Existing interfaces are never re-homed, so without this the setting
# above changes nothing.
#
# The nodes are terminated rather than drained and replaced one by one: this
# procedure runs before any workload is installed, and the managed node group
# brings the capacity straight back. On a cluster that already carries traffic,
# roll the node group instead (`aws eks update-nodegroup-version --force`).
roll_nodes() {
    local context="$1" region="$2" cluster="$3" subnet_csv="$4"

    local before
    mapfile -t before < <(node_instance_ids "$region" "$cluster")

    if [ "${#before[@]}" -eq 0 ]; then
        echo "ERROR: no running node found for $cluster." >&2
        return 1
    fi

    local converted
    mapfile -t converted < <(custom_networking_instance_ids "$region" "$subnet_csv")

    if [ "${#converted[@]}" -ge "${#before[@]}" ]; then
        echo "    ${#converted[@]}/${#before[@]} nodes already use the pod subnets, no roll needed"
        return 0
    fi

    echo "    Terminating ${#before[@]} node(s) so the node group replaces them"
    aws ec2 terminate-instances --region "$region" --instance-ids "${before[@]}" >/dev/null

    local deadline=$((SECONDS + NODE_ROLL_TIMEOUT_SECONDS))
    while true; do
        mapfile -t converted < <(custom_networking_instance_ids "$region" "$subnet_csv")

        local ready
        ready="$(kubectl --context "$context" get nodes -o json 2>/dev/null |
            jq -r '[.items[]
                     | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))]
                   | length' || echo 0)"

        if [ "${#converted[@]}" -ge "${#before[@]}" ] && [ "$ready" -ge "${#before[@]}" ]; then
            echo "    ${#converted[@]} node(s) rejoined with an interface in the pod subnets"
            break
        fi

        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: only ${#converted[@]}/${#before[@]} node(s) attached an interface in the pod subnets" >&2
            echo "       within ${NODE_ROLL_TIMEOUT_SECONDS}s ($ready node(s) Ready)." >&2
            echo "       Check the aws-node logs: kubectl --context $context -n kube-system logs -l k8s-app=aws-node -c aws-node" >&2
            return 1
        fi

        echo "    ${#converted[@]}/${#before[@]} node(s) converted, $ready Ready, waiting ..."
        sleep "$NODE_ROLL_POLL_INTERVAL_SECONDS"
    done
}

if [ $# -ge 1 ]; then
    configure_slot "$1"
else
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        configure_slot "$i"
    done
fi

echo
echo "VPC CNI custom networking is configured."
echo "Pods scheduled from now on are addressed out of the VPC secondary CIDR,"
echo "which no Transit Gateway route table knows about. Submariner is therefore"
echo "the only owner of cross-region pod traffic, which is the point."
