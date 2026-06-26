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

set -euo pipefail

###############################################################################
# User-configurable defaults                                                  #
###############################################################################

export REGION_0=${REGION_0:-eu-west-2}
export REGION_1=${REGION_1:-eu-west-3}

# Path to Terraform root (relative to this script). With the 3-state layout
# (vpc/, infra/, app/), most outputs needed for environment setup live in
# infra/. Override TF_DIR if using an alternate state location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TF_DIR="${TF_DIR:-${SCRIPT_DIR}/../terraform/infra}"
APP_TF_DIR="${APP_TF_DIR:-${SCRIPT_DIR}/../terraform/app}"

###############################################################################
# Retrieve Terraform outputs                                                  #
###############################################################################

echo "Fetching Terraform outputs from ${TF_DIR} ..."

TF_OUTPUT=$(terraform -chdir="${TF_DIR}" output -json)

# Region 0
CLUSTER_0=$(echo "${TF_OUTPUT}" | jq -r '.ecs_cluster_region_0_id.value // empty' | awk -F'/' '{print $NF}')
ALB_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.region_0_alb_endpoint.value // empty')
NLB_GRPC_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.region_0_nlb_grpc_endpoint.value // empty')
NLB_RAFT_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.nlb_raft_region_0_dns_name.value // empty')
export CLUSTER_0 ALB_ENDPOINT_0 NLB_GRPC_ENDPOINT_0 NLB_RAFT_ENDPOINT_0

# Region 1
CLUSTER_1=$(echo "${TF_OUTPUT}" | jq -r '.ecs_cluster_region_1_id.value // empty' | awk -F'/' '{print $NF}')
ALB_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.region_1_alb_endpoint.value // empty')
NLB_GRPC_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.region_1_nlb_grpc_endpoint.value // empty')
NLB_RAFT_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.nlb_raft_region_1_dns_name.value // empty')
export CLUSTER_1 ALB_ENDPOINT_1 NLB_GRPC_ENDPOINT_1 NLB_RAFT_ENDPOINT_1

# Aurora Global Database
AURORA_GLOBAL_CLUSTER_ID=$(echo "${TF_OUTPUT}" | jq -r '.aurora_global_cluster_id.value // empty')
AURORA_PRIMARY_ENDPOINT=$(echo "${TF_OUTPUT}" | jq -r '.aurora_primary_endpoint.value // empty')
AURORA_SECONDARY_ENDPOINT=$(echo "${TF_OUTPUT}" | jq -r '.aurora_secondary_endpoint.value // empty')
export AURORA_GLOBAL_CLUSTER_ID AURORA_PRIMARY_ENDPOINT AURORA_SECONDARY_ENDPOINT

# Admin credentials (from the app state)
echo "Fetching credentials from ${APP_TF_DIR} ..."
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS=$(terraform -chdir="${APP_TF_DIR}" output -raw admin_user_password 2>/dev/null || echo "")
export ADMIN_USER ADMIN_PASS

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
