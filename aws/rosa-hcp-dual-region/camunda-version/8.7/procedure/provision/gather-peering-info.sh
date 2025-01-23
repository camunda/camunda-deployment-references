#!/bin/bash
set -euo pipefail

cd region1
CLUSTER_1_NAME=$(terraform console <<<local.rosa_cluster_1_name | jq -r)

# First cluster
CLUSTER_1_INFO=$(rosa describe cluster --cluster "$CLUSTER_1_NAME" --output json)
CLUSTER_1_REGION=$(echo "$CLUSTER_1_INFO" | jq -r '.region.id')
CLUSTER_1_SUBNET_ID=$(echo "$CLUSTER_1_INFO" | jq -r '.aws.subnet_ids[0]')
CLUSTER_1_VPC_ID=$(aws ec2 describe-subnets --subnet-ids "$CLUSTER_1_SUBNET_ID" --query "Subnets[0].VpcId" --region "$CLUSTER_1_REGION" --output text)
CLUSTER_1_VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$CLUSTER_1_VPC_ID" --region "$CLUSTER_1_REGION" | jq -r '.Vpcs[0].CidrBlock')
CLUSTER_1_ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables --region "$CLUSTER_1_REGION" --filters "Name=vpc-id,Values=$CLUSTER_1_VPC_ID" --query "RouteTables[*].{ID:RouteTableId,Routes:Routes}")
CLUSTER_1_PUBLIC_ROUTE_TABLE_ID=$(echo "$CLUSTER_1_ROUTE_TABLE_IDS" | jq -r '.[] | select((.Routes // []) | any(.GatewayId | (if . == null then false else startswith("igw-") end))) | .ID' | sort -u)

CLUSTER_1_PRIVATE_ROUTE_TABLE_IDS=$(echo "$CLUSTER_1_ROUTE_TABLE_IDS" | jq -r '.[] | .ID' | grep -vxFf <(echo "$CLUSTER_1_ROUTE_TABLE_IDS" | jq -r '.[] | select((.Routes // []) | any(.GatewayId | (if . == null then false else startswith("igw-") end))) | .ID') | sort -u)

CLUSTER_1_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$CLUSTER_1_VPC_ID" "Name=description,Values=default worker security group" --region "$CLUSTER_1_REGION" | jq -r '.SecurityGroups[0].GroupId')
CLUSTER_1_PRIVATE_ROUTE_TABLE_IDS_JSON=$(echo "$CLUSTER_1_PRIVATE_ROUTE_TABLE_IDS" | jq -R -s 'split("\n") | map(select(length > 0))')

cd -

# Second cluster
cd region2
CLUSTER_2_NAME=$(terraform console <<<local.rosa_cluster_2_name | jq -r)

CLUSTER_2_INFO=$(rosa describe cluster --cluster "$CLUSTER_2_NAME" --output json)
CLUSTER_2_REGION=$(echo "$CLUSTER_2_INFO" | jq -r '.region.id')
CLUSTER_2_SUBNET_ID=$(echo "$CLUSTER_2_INFO" | jq -r '.aws.subnet_ids[0]')
CLUSTER_2_VPC_ID=$(aws ec2 describe-subnets --subnet-ids "$CLUSTER_2_SUBNET_ID" --query "Subnets[0].VpcId" --region "$CLUSTER_2_REGION" --output text)
CLUSTER_2_VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$CLUSTER_2_VPC_ID" --region "$CLUSTER_2_REGION" | jq -r '.Vpcs[0].CidrBlock')
CLUSTER_2_ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables --region "$CLUSTER_2_REGION" --filters "Name=vpc-id,Values=$CLUSTER_2_VPC_ID" --query "RouteTables[*].{ID:RouteTableId,Routes:Routes}")
CLUSTER_2_PUBLIC_ROUTE_TABLE_ID=$(echo "$CLUSTER_2_ROUTE_TABLE_IDS" | jq -r '.[] | select((.Routes // []) | any(.GatewayId | (if . == null then false else startswith("igw-") end))) | .ID' | sort -u)

CLUSTER_2_PRIVATE_ROUTE_TABLE_IDS=$(echo "$CLUSTER_2_ROUTE_TABLE_IDS" | jq -r '.[] | .ID' | grep -vxFf <(echo "$CLUSTER_2_ROUTE_TABLE_IDS" | jq -r '.[] | select((.Routes // []) | any(.GatewayId | (if . == null then false else startswith("igw-") end))) | .ID') | sort -u)

CLUSTER_2_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$CLUSTER_2_VPC_ID" "Name=description,Values=default worker security group" --region "$CLUSTER_2_REGION" | jq -r '.SecurityGroups[0].GroupId')
CLUSTER_2_PRIVATE_ROUTE_TABLE_IDS_JSON=$(echo "$CLUSTER_2_PRIVATE_ROUTE_TABLE_IDS" | jq -R -s 'split("\n") | map(select(length > 0))')

cd -

OWNER_JSON=$(jq -n \
  --arg region "$CLUSTER_1_REGION" \
  --arg vpc_cidr_block "$CLUSTER_1_VPC_CIDR" \
  --arg vpc_id "$CLUSTER_1_VPC_ID" \
  --arg security_group_id "$CLUSTER_1_SECURITY_GROUP_ID" \
  --arg public_route_table_id "$CLUSTER_1_PUBLIC_ROUTE_TABLE_ID" \
  --argjson private_route_table_ids "$CLUSTER_1_PRIVATE_ROUTE_TABLE_IDS_JSON" \
  '{
    region: $region,
    vpc_cidr_block: $vpc_cidr_block,
    vpc_id: $vpc_id,
    security_group_id: $security_group_id,
    public_route_table_id: $public_route_table_id,
    private_route_table_ids: $private_route_table_ids
  }')

ACCEPTER_JSON=$(jq -n \
  --arg region "$CLUSTER_2_REGION" \
  --arg vpc_cidr_block "$CLUSTER_2_VPC_CIDR" \
  --arg vpc_id "$CLUSTER_2_VPC_ID" \
  --arg security_group_id "$CLUSTER_2_SECURITY_GROUP_ID" \
  --arg public_route_table_id "$CLUSTER_2_PUBLIC_ROUTE_TABLE_ID" \
  --argjson private_route_table_ids "$CLUSTER_2_PRIVATE_ROUTE_TABLE_IDS_JSON" \
  '{
    region: $region,
    vpc_cidr_block: $vpc_cidr_block,
    vpc_id: $vpc_id,
    security_group_id: $security_group_id,
    public_route_table_id: $public_route_table_id,
    private_route_table_ids: $private_route_table_ids
  }')

echo "Terraform Variables for Owner ($CLUSTER_1_NAME):"
echo "$OWNER_JSON"
export OWNER_JSON

echo "Terraform Variables for Accepter ($CLUSTER_2_NAME):"
echo "$ACCEPTER_JSON"
export ACCEPTER_JSON
