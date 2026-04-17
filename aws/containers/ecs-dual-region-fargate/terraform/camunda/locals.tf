################################
# Computed Values             #
################################

locals {
  prefix = var.cluster_name

  # Truncate prefix for AWS resources with name length limits (e.g., ALB target groups: 32 chars)
  prefix_truncated = substr(local.prefix, 0, 14)

  # Region-specific prefixes
  prefix_region_0 = "${local.prefix}-r0"
  prefix_region_1 = "${local.prefix}-r1"

  # Zeebe dual-region cluster configuration
  # Even-numbered brokers (0, 2, 4, 6) in region 0
  # Odd-numbered brokers (1, 3, 5, 7) in region 1
  cluster_size       = 4
  replication_factor = 4 # REGION_AWARE: sum of numberOfReplicas across regions (2+2) must equal replicationFactor
  partition_count    = 4
  brokers_per_region = 2

  # Shorthand for infra layer outputs — keeps resource references concise
  infra = data.terraform_remote_state.infra.outputs

  # Aurora Global DB JDBC URL with AWS JDBC Wrapper.
  #
  # The `failover` plugin detects Aurora Global Database topology and requires
  # `globalClusterInstanceHostPatterns` to locate instances across regions.
  # Instance endpoints use the cluster resource ID with the "cluster-" prefix
  # stripped: cluster-XXXXXXXX -> ?.XXXXXXXX.<region>.rds.amazonaws.com
  #
  # Both orchestration clusters share one writer endpoint (region 0 primary);
  # the failover plugin re-connects automatically after a Global DB failover.
  aurora_instance_pattern_region_0 = "?.${trimprefix(local.infra.aurora_primary_cluster_resource_id, "cluster-")}.${data.aws_region.region_0.id}.rds.amazonaws.com"
  aurora_instance_pattern_region_1 = "?.${trimprefix(local.infra.aurora_secondary_cluster_resource_id, "cluster-")}.${data.aws_region.region_1.id}.rds.amazonaws.com"

  aurora_jdbc_url = join("", [
    "jdbc:aws-wrapper:postgresql://",
    local.infra.aurora_primary_cluster_endpoint,
    ":5432/",
    var.db_name,
    "?wrapperPlugins=iam,failover",
    "&globalClusterInstanceHostPatterns=",
    local.aurora_instance_pattern_region_0,
    ",",
    local.aurora_instance_pattern_region_1,
  ])
}
