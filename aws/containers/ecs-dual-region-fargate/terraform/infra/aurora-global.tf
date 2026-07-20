################################################################
#                 Aurora Global Database                        #
################################################################

module "aurora_global" {
  count  = var.secondary_storage_type == "rdbms" ? 1 : 0
  source = "../../../../modules/aurora-global"

  providers = {
    aws.primary   = aws
    aws.secondary = aws.accepter
  }

  global_cluster_identifier = "${local.prefix}-global-db"

  engine = local.aurora_engine

  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  postgresql_engine_version = "18.3"
  # renovate: datasource=custom.aurora-mysql-camunda depName=aurora-mysql versioning=loose
  mysql_engine_version = "8.4.7"

  auto_minor_version_upgrade = false
  database_name              = var.db_name

  master_username  = var.db_admin_username
  master_password  = local.db_admin_password_effective
  iam_auth_enabled = var.db_iam_auth_enabled

  # Primary cluster (region 0 — writer)
  primary_cluster_name       = "${local.prefix_region_0}-camunda-db"
  primary_vpc_id             = local.vpc.region_0_vpc_id
  primary_subnet_ids         = local.vpc.region_0_private_subnet_ids
  primary_cidr_blocks        = [local.vpc.region_0_vpc_cidr, local.vpc.region_1_vpc_cidr]
  primary_availability_zones = local.region_0_azs
  primary_num_instances      = 1

  # Secondary cluster (region 1 — read replicas)
  secondary_cluster_name  = "${local.prefix_region_1}-camunda-db"
  secondary_vpc_id        = local.vpc.region_1_vpc_id
  secondary_subnet_ids    = local.vpc.region_1_private_subnet_ids
  secondary_cidr_blocks   = [local.vpc.region_0_vpc_cidr, local.vpc.region_1_vpc_cidr]
  secondary_num_instances = 1
}
