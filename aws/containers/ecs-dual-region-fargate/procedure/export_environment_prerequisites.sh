#!/bin/bash

###############################################################################
# Export environment variables for ECS Dual-Region Fargate procedures         #
#                                                                             #
# Usage:                                                                      #
#   . ./export_environment_prerequisites.sh                                   #
#                                                                             #
# Requires: terraform CLI, awscli, jq                                        #
# Must be sourced (not executed) to export variables to current shell.        #
###############################################################################

###############################################################################
# User-configurable defaults                                                  #
###############################################################################

export REGION_0=${REGION_0:-eu-west-2}
export REGION_1=${REGION_1:-eu-west-3}

# Path to Terraform root — anchored to the git repo root so this script works
# regardless of which directory it is sourced from.
# Override TF_DIR to point at an alternate state location.
_GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
TF_DIR="${TF_DIR:-${_GIT_ROOT}/aws/containers/ecs-dual-region-fargate/terraform/infra}"
unset _GIT_ROOT

###############################################################################
# Retrieve Terraform outputs                                                  #
###############################################################################

echo "Fetching Terraform outputs from ${TF_DIR} ..."

TF_OUTPUT=$(terraform -chdir="${TF_DIR}" output -json)

# Override region defaults from Terraform outputs if available
_TF_REGION_0=$(echo "${TF_OUTPUT}" | jq -r '.region_0.value // empty')
_TF_REGION_1=$(echo "${TF_OUTPUT}" | jq -r '.region_1.value // empty')
[ -n "${_TF_REGION_0}" ] && export REGION_0="${_TF_REGION_0}"
[ -n "${_TF_REGION_1}" ] && export REGION_1="${_TF_REGION_1}"

# Region 0
CLUSTER_0=$(echo "${TF_OUTPUT}" | jq -r '.ecs_cluster_region_0_id.value | split("/") | last')
ALB_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.region_0_alb_endpoint.value')
NLB_GRPC_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.region_0_nlb_grpc_endpoint.value')
NLB_RAFT_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.nlb_raft_region_0_dns_name.value')
export CLUSTER_0 ALB_ENDPOINT_0 NLB_GRPC_ENDPOINT_0 NLB_RAFT_ENDPOINT_0

# Region 1
CLUSTER_1=$(echo "${TF_OUTPUT}" | jq -r '.ecs_cluster_region_1_id.value | split("/") | last')
ALB_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.region_1_alb_endpoint.value')
NLB_GRPC_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.region_1_nlb_grpc_endpoint.value')
NLB_RAFT_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.nlb_raft_region_1_dns_name.value')
export CLUSTER_1 ALB_ENDPOINT_1 NLB_GRPC_ENDPOINT_1 NLB_RAFT_ENDPOINT_1

# Aurora Global Database
AURORA_GLOBAL_CLUSTER_ID=$(echo "${TF_OUTPUT}" | jq -r '.aurora_global_cluster_id.value')
AURORA_PRIMARY_ENDPOINT=$(echo "${TF_OUTPUT}" | jq -r '.aurora_primary_endpoint.value')
AURORA_SECONDARY_ENDPOINT=$(echo "${TF_OUTPUT}" | jq -r '.aurora_secondary_endpoint.value')
export AURORA_GLOBAL_CLUSTER_ID AURORA_PRIMARY_ENDPOINT AURORA_SECONDARY_ENDPOINT

###############################################################################
# Summary                                                                     #
###############################################################################

cat <<EOF

=== ECS Dual-Region Environment ===

Region 0 (${REGION_0}):
  ECS Cluster:    ${CLUSTER_0}
  ALB (HTTP):     ${ALB_ENDPOINT_0}
  NLB (gRPC):     ${NLB_GRPC_ENDPOINT_0}
  NLB (Raft):     ${NLB_RAFT_ENDPOINT_0}

Region 1 (${REGION_1}):
  ECS Cluster:    ${CLUSTER_1}
  ALB (HTTP):     ${ALB_ENDPOINT_1}
  NLB (gRPC):     ${NLB_GRPC_ENDPOINT_1}
  NLB (Raft):     ${NLB_RAFT_ENDPOINT_1}

Aurora Global Database:
  Global Cluster: ${AURORA_GLOBAL_CLUSTER_ID}
  Primary (W):    ${AURORA_PRIMARY_ENDPOINT}
  Secondary (R):  ${AURORA_SECONDARY_ENDPOINT}

EOF
