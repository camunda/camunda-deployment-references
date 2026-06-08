################################
# Computed Values             #
################################

resource "random_id" "bucket_suffix" {
  byte_length = 3 # 6 hex characters
}

locals {
  prefix        = var.cluster_name
  bucket_suffix = random_id.bucket_suffix.hex

  # Region configuration (derived from variables)
  owner = {
    region         = var.region_0
    vpc_cidr_block = var.region_0_cidr
  }
  accepter = {
    region         = var.region_1
    vpc_cidr_block = var.region_1_cidr
  }

  # Truncate prefix for AWS resources with name length limits (e.g., ALB target groups: 32 chars)
  prefix_truncated = substr(local.prefix, 0, 14)

  # Region-specific prefixes
  prefix_region_0 = "${local.prefix}-r0"
  prefix_region_1 = "${local.prefix}-r1"
}
