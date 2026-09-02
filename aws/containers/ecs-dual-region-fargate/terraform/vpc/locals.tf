################################
# Computed Values             #
################################

locals {
  prefix          = var.cluster_name
  prefix_region_0 = "${local.prefix}-r0"
  prefix_region_1 = "${local.prefix}-r1"

  # Single source of truth — every downstream resource references local.region_N_*
  # rather than the module output or the variable directly. This is what lets
  # the rest of this state stay agnostic about byo_vpc.

  region_0_vpc_id                  = var.byo_vpc ? var.region_0_vpc_id : module.vpc_region_0[0].vpc_id
  region_0_vpc_cidr                = var.byo_vpc ? var.region_0_vpc_cidr : module.vpc_region_0[0].vpc_cidr_block
  region_0_private_subnet_ids      = var.byo_vpc ? var.region_0_private_subnet_ids : module.vpc_region_0[0].private_subnets
  region_0_public_subnet_ids       = var.byo_vpc ? var.region_0_public_subnet_ids : module.vpc_region_0[0].public_subnets
  region_0_private_route_table_ids = var.byo_vpc ? var.region_0_private_route_table_ids : module.vpc_region_0[0].private_route_table_ids

  region_1_vpc_id                  = var.byo_vpc ? var.region_1_vpc_id : module.vpc_region_1[0].vpc_id
  region_1_vpc_cidr                = var.byo_vpc ? var.region_1_vpc_cidr : module.vpc_region_1[0].vpc_cidr_block
  region_1_private_subnet_ids      = var.byo_vpc ? var.region_1_private_subnet_ids : module.vpc_region_1[0].private_subnets
  region_1_public_subnet_ids       = var.byo_vpc ? var.region_1_public_subnet_ids : module.vpc_region_1[0].public_subnets
  region_1_private_route_table_ids = var.byo_vpc ? var.region_1_private_route_table_ids : module.vpc_region_1[0].private_route_table_ids
}
