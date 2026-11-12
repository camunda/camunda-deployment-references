# Same shapes as the storage stage's outputs: the Camunda stages of both regions take
# these as their secondary_storage and rds_db_connect_policy_arn instead.

output "secondary_storage" {
  value = {
    type                   = "rdbms"
    host                   = aws_rds_global_cluster.this.endpoint
    port                   = 5432
    database_name          = var.database_name
    jdbc_url               = "jdbc:aws-wrapper:postgresql://${aws_rds_global_cluster.this.endpoint}:5432/${var.database_name}?${local.jdbc_query}"
    jdbc_driver_class_name = "software.amazon.jdbc.Driver"
    iam_auth_enabled       = var.iam_auth_enabled
  }
  description = "Connection settings through the global writer endpoint"
}

output "rds_db_connect_policy_arns" {
  value       = { for user, p in aws_iam_policy.rds_db_connect : user => p.arn }
  description = "Per IAM database user: a policy that allows connecting to both clusters. Replace the single-cluster policy of the storage stage with it."
}

output "global_cluster_identifier" {
  value       = aws_rds_global_cluster.this.id
  description = "Set it as global_cluster_identifier on the storage stage, so that Terraform does not plan to detach the cluster"
}

output "secondary_security_group_id" {
  value       = module.secondary.security_group_id
  description = "Security group of the secondary cluster"
}

output "db_seed_done" {
  value       = "global"
  description = "Placeholder so that the Camunda stage takes the same inputs as with the storage stage. The database users were created before the global cluster."
}
