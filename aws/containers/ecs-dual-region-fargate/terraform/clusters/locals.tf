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
  cluster_size       = 8
  replication_factor = 4
  partition_count    = 8
  brokers_per_region = 4
}
