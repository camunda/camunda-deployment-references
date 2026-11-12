# Turns the standalone Aurora cluster of the storage stage into an Aurora Global Database
# and adds a secondary cluster in the second region. The existing cluster is not replaced:
# the global cluster is created from it (source_db_cluster_identifier).
#
# Before you apply it:
#   1. The existing cluster must run on an r-class or serverless instance: Global Databases
#      do not support db.t3 / db.t4g. Resizing is done through the storage stage
#      (db_instance_class) and is not instant; see the runbook.
#   2. Afterwards, set global_cluster_identifier on the storage stage to this root's
#      output, so that Terraform does not plan to detach the cluster again.

data "aws_caller_identity" "current" {}

resource "aws_rds_global_cluster" "this" {
  region = var.region_a

  global_cluster_identifier    = "${var.prefix}-global-db"
  source_db_cluster_identifier = var.source_cluster_arn
  force_destroy                = var.force_destroy

  lifecycle {
    # The source is only read when the global cluster is created.
    ignore_changes = [source_db_cluster_identifier]
  }
}

module "secondary" {
  source = "../../../../modules/aurora-global-member"

  region                    = var.region_b
  cluster_identifier        = "${var.prefix}-camunda-db-b"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  is_primary                = false

  engine_version = var.engine_version
  instance_class = var.secondary_instance_class
  num_instances  = var.secondary_num_instances

  vpc_id                  = var.vpc_id_b
  subnet_ids              = var.private_subnet_ids_b
  allowed_cidr_blocks     = [var.vpc_cidr_a, var.vpc_cidr_b]
  iam_auth_enabled        = var.iam_auth_enabled
  skip_final_snapshot     = true
  apply_immediately       = true
  backup_retention_period = 7
}

locals {
  # The wrapper enumerates the instances of every region from these patterns.
  primary_host_pattern = "?.${replace(var.source_cluster_endpoint, "${var.source_cluster_identifier}.cluster-", "")}"
  host_patterns        = "${local.primary_host_pattern},${module.secondary.instance_host_pattern}"

  jdbc_parameters = {
    wrapperPlugins                    = "initialConnection,iam,failover"
    globalClusterInstanceHostPatterns = local.host_patterns
    failoverTimeoutMs                 = "60000"
    sslmode                           = "require"
  }
  jdbc_query = join("&", [for k, v in local.jdbc_parameters : "${k}=${v}"])
}

# After a failover the writer is the other cluster, so a user's connect policy must name
# both clusters. IAM policies are global: the same policy serves both regions.
resource "aws_iam_policy" "rds_db_connect" {
  for_each = toset(var.db_users)

  name        = "${var.prefix}-rds-db-connect-${each.key}-global"
  description = "Allow ECS tasks to connect as '${each.key}' to either cluster of the global database"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRDSDBConnect"
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = [
          "arn:aws:rds-db:${var.region_a}:${data.aws_caller_identity.current.account_id}:dbuser:${var.source_cluster_resource_id}/${each.key}",
          "arn:aws:rds-db:${var.region_b}:${data.aws_caller_identity.current.account_id}:dbuser:${module.secondary.cluster_resource_id}/${each.key}",
        ]
      }
    ]
  })
}
