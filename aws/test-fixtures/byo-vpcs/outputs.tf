# Outputs match the field names the ecs-dual-region-fargate vpc/ state's
# byo_vpc tfvars expect — copy these directly into the BYO test.

output "region_0_vpc_id" {
  value = module.vpc_region_0.vpc_id
}

output "region_0_vpc_cidr" {
  value = module.vpc_region_0.vpc_cidr_block
}

output "region_0_private_subnet_ids" {
  value = module.vpc_region_0.private_subnets
}

output "region_0_public_subnet_ids" {
  value = module.vpc_region_0.public_subnets
}

output "region_0_private_route_table_ids" {
  value = module.vpc_region_0.private_route_table_ids
}

output "region_1_vpc_id" {
  value = module.vpc_region_1.vpc_id
}

output "region_1_vpc_cidr" {
  value = module.vpc_region_1.vpc_cidr_block
}

output "region_1_private_subnet_ids" {
  value = module.vpc_region_1.private_subnets
}

output "region_1_public_subnet_ids" {
  value = module.vpc_region_1.public_subnets
}

output "region_1_private_route_table_ids" {
  value = module.vpc_region_1.private_route_table_ids
}
