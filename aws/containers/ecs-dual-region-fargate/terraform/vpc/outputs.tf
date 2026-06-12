################################################################
#                     VPC State Output Contract                 #
#                                                                #
# This is the public interface that terraform/infra/ consumes   #
# via terraform_remote_state. Adding outputs is safe; removing  #
# or renaming is a breaking change.                              #
#                                                                #
# Naming convention: region_N_<thing>.                          #
################################################################

# ---------------------------- Region 0 ----------------------------

output "region_0_vpc_id" {
  value       = local.region_0_vpc_id
  description = "VPC ID in region 0 (created here or supplied via BYO)"
}

output "region_0_vpc_cidr" {
  value       = local.region_0_vpc_cidr
  description = "VPC CIDR block in region 0"
}

output "region_0_private_subnet_ids" {
  value       = local.region_0_private_subnet_ids
  description = "Private subnet IDs in region 0 (used by ECS tasks and Aurora)"
}

output "region_0_public_subnet_ids" {
  value       = local.region_0_public_subnet_ids
  description = "Public subnet IDs in region 0 (used for ALBs)"
}

output "region_0_private_route_table_ids" {
  value       = local.region_0_private_route_table_ids
  description = "Route table IDs associated with region 0 private subnets"
}

output "region_0_internet_gateway_id" {
  value       = var.byo_vpc ? null : module.vpc_region_0[0].igw_id
  description = "Internet Gateway ID in region 0 (null in BYO mode — customer-managed)"
}

# ---------------------------- Region 1 ----------------------------

output "region_1_vpc_id" {
  value       = local.region_1_vpc_id
  description = "VPC ID in region 1 (created here or supplied via BYO)"
}

output "region_1_vpc_cidr" {
  value       = local.region_1_vpc_cidr
  description = "VPC CIDR block in region 1"
}

output "region_1_private_subnet_ids" {
  value       = local.region_1_private_subnet_ids
  description = "Private subnet IDs in region 1 (used by ECS tasks and Aurora)"
}

output "region_1_public_subnet_ids" {
  value       = local.region_1_public_subnet_ids
  description = "Public subnet IDs in region 1 (used for ALBs)"
}

output "region_1_private_route_table_ids" {
  value       = local.region_1_private_route_table_ids
  description = "Route table IDs associated with region 1 private subnets"
}

output "region_1_internet_gateway_id" {
  value       = var.byo_vpc ? null : module.vpc_region_1[0].igw_id
  description = "Internet Gateway ID in region 1 (null in BYO mode — customer-managed)"
}

# ---------------------------- Cross-Region ----------------------------

output "networking_mode" {
  value       = var.networking_mode
  description = "Cross-region networking mode: 'transit_gateway' or 'vpc_peering'"
}

output "region_0_transit_gateway_id" {
  value       = var.networking_mode == "transit_gateway" ? module.transit_gateway[0].owner_transit_gateway_id : null
  description = "TGW ID in region 0 (null when networking_mode = vpc_peering)"
}

output "region_1_transit_gateway_id" {
  value       = var.networking_mode == "transit_gateway" ? module.transit_gateway[0].accepter_transit_gateway_id : null
  description = "TGW ID in region 1 (null when networking_mode = vpc_peering)"
}

output "vpc_peering_connection_id" {
  value       = var.networking_mode == "vpc_peering" ? aws_vpc_peering_connection.cross_region[0].id : null
  description = "VPC Peering connection ID (null when networking_mode = transit_gateway)"
}

# ---------------------------- DNS Resolver (optional) ----------------------------

output "region_0_route53_resolver_endpoint_id" {
  value       = var.enable_cross_region_dns_resolver ? aws_route53_resolver_endpoint.outbound_region_0[0].id : null
  description = "Region 0 outbound resolver endpoint ID (null when enable_cross_region_dns_resolver = false)"
}

output "region_1_route53_resolver_endpoint_id" {
  value       = var.enable_cross_region_dns_resolver ? aws_route53_resolver_endpoint.outbound_region_1[0].id : null
  description = "Region 1 outbound resolver endpoint ID (null when enable_cross_region_dns_resolver = false)"
}

# ---------------------------- Passthrough ----------------------------
# These are convenience outputs so infra/ doesn't need its own copies
# of the region names and prefix.

output "cluster_name" {
  value       = var.cluster_name
  description = "Cluster name prefix (passed through from var.cluster_name)"
}

output "region_0" {
  value       = var.region_0
  description = "AWS region for region 0 (owner)"
}

output "region_1" {
  value       = var.region_1
  description = "AWS region for region 1 (accepter)"
}
