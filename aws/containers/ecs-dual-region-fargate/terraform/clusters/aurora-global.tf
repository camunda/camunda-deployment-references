################################################################
#                 Aurora Global Database                        #
################################################################

module "aurora_global" {
  source = "../../../../modules/aurora-global"

  providers = {
    aws.primary   = aws
    aws.secondary = aws.accepter
  }

  global_cluster_identifier = "${local.prefix}-global-db"

  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  engine_version             = "17.9"
  auto_minor_version_upgrade = false
  database_name              = var.db_name

  master_username  = var.db_admin_username
  master_password  = local.db_admin_password_effective
  iam_auth_enabled = var.db_iam_auth_enabled

  # Primary cluster (region 0 — writer)
  primary_cluster_name       = "${local.prefix_region_0}-camunda-db"
  primary_vpc_id             = module.vpc_region_0.vpc_id
  primary_subnet_ids         = module.vpc_region_0.private_subnets
  primary_cidr_blocks        = [local.owner.vpc_cidr_block, local.accepter.vpc_cidr_block]
  primary_availability_zones = module.vpc_region_0.azs
  primary_num_instances      = 1

  # Secondary cluster (region 1 — read replicas)
  secondary_cluster_name  = "${local.prefix_region_1}-camunda-db"
  secondary_vpc_id        = module.vpc_region_1.vpc_id
  secondary_subnet_ids    = module.vpc_region_1.private_subnets
  secondary_cidr_blocks   = [local.owner.vpc_cidr_block, local.accepter.vpc_cidr_block]
  secondary_num_instances = 1
}
