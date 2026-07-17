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

# Path to Terraform root (relative to this script). With the 3-state layout
# (vpc/, infra/, app/), all outputs needed for environment setup live in
# infra/. Override TF_DIR if using an alternate state location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TF_DIR="${TF_DIR:-${SCRIPT_DIR}/../terraform/infra}"

###############################################################################
# Retrieve Terraform outputs                                                  #
###############################################################################

echo "Fetching Terraform outputs from ${TF_DIR} ..."

TF_OUTPUT=$(terraform -chdir="${TF_DIR}" output -json)

# Regions — read from state so they always match the actual deployment
REGION_0=$(echo "${TF_OUTPUT}" | jq -r '.region_0.value // empty')
REGION_1=$(echo "${TF_OUTPUT}" | jq -r '.region_1.value // empty')
export REGION_0 REGION_1

# Region 0
CLUSTER_0=$(echo "${TF_OUTPUT}" | jq -r '.ecs_cluster_region_0_id.value // "" | split("/") | last')
ALB_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.region_0_alb_endpoint.value // empty')
NLB_GRPC_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.region_0_nlb_grpc_endpoint.value // empty')
NLB_RAFT_ENDPOINT_0=$(echo "${TF_OUTPUT}" | jq -r '.nlb_raft_region_0_dns_name.value // empty')
export CLUSTER_0 ALB_ENDPOINT_0 NLB_GRPC_ENDPOINT_0 NLB_RAFT_ENDPOINT_0

# Region 1
CLUSTER_1=$(echo "${TF_OUTPUT}" | jq -r '.ecs_cluster_region_1_id.value // "" | split("/") | last')
ALB_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.region_1_alb_endpoint.value // empty')
NLB_GRPC_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.region_1_nlb_grpc_endpoint.value // empty')
NLB_RAFT_ENDPOINT_1=$(echo "${TF_OUTPUT}" | jq -r '.nlb_raft_region_1_dns_name.value // empty')
export CLUSTER_1 ALB_ENDPOINT_1 NLB_GRPC_ENDPOINT_1 NLB_RAFT_ENDPOINT_1

# Aurora Global Database
# AURORA_GLOBAL_WRITER_ENDPOINT — global endpoint that survives failover (use in JDBC URLs)
# AURORA_PRIMARY_ENDPOINT       — regional writer endpoint for the primary cluster (region 0)
AURORA_GLOBAL_CLUSTER_ID=$(echo "${TF_OUTPUT}" | jq -r '.aurora_global_cluster_id.value // empty')
AURORA_GLOBAL_WRITER_ENDPOINT=$(echo "${TF_OUTPUT}" | jq -r '.aurora_global_writer_endpoint.value // empty')
AURORA_PRIMARY_ENDPOINT=$(echo "${TF_OUTPUT}" | jq -r '.aurora_primary_cluster_endpoint.value // empty')
AURORA_SECONDARY_ENDPOINT=$(echo "${TF_OUTPUT}" | jq -r '.aurora_secondary_endpoint.value // empty')
export AURORA_GLOBAL_CLUSTER_ID AURORA_GLOBAL_WRITER_ENDPOINT AURORA_PRIMARY_ENDPOINT AURORA_SECONDARY_ENDPOINT

# Admin credentials
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS=$(echo "${TF_OUTPUT}" | jq -r '.admin_user_password.value // empty')
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
  Global Writer:  ${AURORA_GLOBAL_WRITER_ENDPOINT}
  Primary (R0):   ${AURORA_PRIMARY_ENDPOINT}
  Secondary (R1): ${AURORA_SECONDARY_ENDPOINT}

EOF
