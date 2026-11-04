# Network contract: these outputs are the inputs of every downstream layer.

output "vpc_id" {
  value       = var.byo_vpc ? var.vpc_id : module.vpc[0].vpc_id
  description = "ID of the VPC"
}

output "vpc_cidr" {
  value       = var.byo_vpc ? var.vpc_cidr : module.vpc[0].vpc_cidr_block
  description = "CIDR block of the VPC"
}

output "private_subnet_ids" {
  value       = var.byo_vpc ? var.private_subnet_ids : module.vpc[0].private_subnets
  description = "Private subnet IDs (ECS tasks, Aurora)"
}

output "public_subnet_ids" {
  value       = var.byo_vpc ? var.public_subnet_ids : module.vpc[0].public_subnets
  description = "Public subnet IDs (internet-facing load balancers)"
}

output "private_route_table_ids" {
  value       = var.byo_vpc ? var.private_route_table_ids : module.vpc[0].private_route_table_ids
  description = "Private route table IDs (needed for peering or transit gateway routes)"
}
