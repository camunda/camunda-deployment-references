output "vpc_id" {
  value       = module.network.vpc_id
  description = "ID of the VPC"
}

output "vpc_cidr" {
  value       = module.network.vpc_cidr
  description = "CIDR block of the VPC"
}

output "private_subnet_ids" {
  value       = module.network.private_subnet_ids
  description = "Private subnet IDs"
}

output "public_subnet_ids" {
  value       = module.network.public_subnet_ids
  description = "Public subnet IDs"
}

output "private_route_table_ids" {
  value       = module.network.private_route_table_ids
  description = "Private route table IDs"
}
