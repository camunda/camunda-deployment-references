################################
# Computed Values             #
################################

resource "random_id" "bucket_suffix" {
  byte_length = 3 # 6 hex characters
}

locals {
  prefix        = var.cluster_name
  bucket_suffix = random_id.bucket_suffix.hex

  # Truncate prefix for AWS resources with name length limits (e.g., ALB target groups: 32 chars)
  prefix_truncated = substr(local.prefix, 0, 14)

  # Region-specific prefixes
  prefix_region_0 = "${local.prefix}-r0"
  prefix_region_1 = "${local.prefix}-r1"

  # AZs of the private subnets, derived from the vpc/ outputs.
  # Used by Aurora to populate the cluster's availability_zones argument.
  region_0_azs = distinct([for s in data.aws_subnet.region_0_private : s.availability_zone])
  region_1_azs = distinct([for s in data.aws_subnet.region_1_private : s.availability_zone])

  # RDBMS engine selection. db_engine (postgresql|mysql) maps to the aurora-global
  # module's engine and the wire port; both derived here so security groups, the
  # DB seed task, and outputs stay consistent.
  aurora_engine = var.db_engine == "mysql" ? "aurora-mysql" : "aurora-postgresql"
  db_port       = var.db_engine == "mysql" ? 3306 : 5432
}
