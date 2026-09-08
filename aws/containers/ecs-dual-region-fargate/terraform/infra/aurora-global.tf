################################################################
#                 Aurora Global Database                        #
################################################################

locals {
  # The JDBC wrapper configuration this reference architecture commits to, kept
  # here rather than as defaults on the pass-through variables so that extending
  # either input cannot silently drop it (a db_extra_wrapper_plugins of
  # ["readWriteSplitting"] would replace a ["efm2"] default, leaving the
  # deployment back on TCP-timeout failure detection with nothing to warn about).
  #
  # efm2 (Enhanced Failure Monitoring v2) detects an unresponsive instance from
  # its own monitoring connection instead of waiting for the TCP timeout, so the
  # failover plugin reacts within seconds of a writer going away. It must load
  # after failover, which the module's append-after-builtins order guarantees.
  db_wrapper_plugins = distinct(concat(["efm2"], var.db_extra_wrapper_plugins))

  # failoverTimeoutMs is the failover plugin's reconnect budget. The wrapper's
  # own default is 300000 (5 min), far longer than an Aurora Global failover
  # takes, so the orchestration cluster would keep retrying a dead writer for
  # that whole window. merge() puts the operator last, so a deployment can
  # retune the value but omitting it cannot revert to the driver default.
  db_url_parameters = merge({ failoverTimeoutMs = "60000" }, var.db_extra_url_parameters)
}

module "aurora_global" {
  count  = var.secondary_storage_type == "rdbms" ? 1 : 0
  source = "../../../../modules/aurora-global"

  providers = {
    aws.primary   = aws
    aws.secondary = aws.accepter
  }

  global_cluster_identifier = "${local.prefix}-global-db"

  engine = local.aurora_engine

  # Engine versions are pinned (and Renovate-tracked) once, on the module's
  # postgresql_engine_version / mysql_engine_version defaults. Overriding them
  # here would duplicate the pins and make Renovate bump both engines in every
  # consumer; set engine_version instead to deviate for a single deployment.

  auto_minor_version_upgrade = false
  database_name              = var.db_name

  master_username       = var.db_admin_username
  master_password       = local.db_admin_password_effective
  iam_auth_enabled      = var.db_iam_auth_enabled
  extra_wrapper_plugins = local.db_wrapper_plugins
  extra_url_parameters  = local.db_url_parameters

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
