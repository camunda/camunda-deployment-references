# Object storage stage. Two kinds of buckets, for two different reasons:
#
#   backup          one per cluster: Camunda writes its backups here and restores from here.
#                   Versioned.
#   node-id-lease   one per zone: ECS has no stable broker identity, so each broker leases a
#                   node index from this bucket with S3 conditional writes. The lease is
#                   scoped to the bucket, so a bucket must never be shared between zones or
#                   clusters. Not versioned: the lease object changes on every renewal.

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global: the account ID keeps them unique without a random suffix.
  name_base = "${var.prefix}-${data.aws_caller_identity.current.account_id}"
}

module "backup" {
  source = "../../../../modules/s3-bucket"

  bucket_name   = "${local.name_base}-backup"
  purpose       = "backup"
  aws_region    = var.aws_region
  force_destroy = var.force_destroy
}

module "lease" {
  source   = "../../../../modules/s3-bucket"
  for_each = var.zones

  bucket_name   = "${local.name_base}-lease-${each.key}"
  purpose       = "node-id-lease"
  aws_region    = var.aws_region
  force_destroy = var.force_destroy
}
