# Storage contract: the Camunda layer builds the RDBMS secondary storage settings from
# these outputs only.

output "secondary_storage" {
  value = {
    type                   = "rdbms"
    host                   = module.aurora.aurora_endpoint
    port                   = module.aurora.aurora_port
    database_name          = var.db_name
    jdbc_url               = "jdbc:aws-wrapper:postgresql://${module.aurora.aurora_endpoint}:${module.aurora.aurora_port}/${var.db_name}?wrapperPlugins=iam"
    jdbc_driver_class_name = "software.amazon.jdbc.Driver"
    iam_auth_enabled       = var.db_iam_auth_enabled
  }
  description = "Connection settings of the secondary storage"
}

output "rds_db_connect_policy_arns" {
  value       = { for user, p in aws_iam_policy.rds_db_connect : user => p.arn }
  description = "Per IAM database user: the policy that allows connecting as that user; attach it to the task role"
}

output "security_group_id" {
  value       = module.aurora.aurora_security_group_id
  description = "Security group of the Aurora cluster"
}

output "cluster_identifier" {
  value       = module.aurora.aurora_cluster_identifier
  description = "Aurora cluster identifier. Use it as source_db_cluster_identifier when creating a global cluster from this one."
}

output "db_seed_done" {
  value       = var.db_seed_enabled ? null_resource.run_db_seed_task[0].id : "disabled"
  description = "Changes once the seed task has run. Pass it to the Camunda layer so that it starts after the database users exist."
}

output "cluster_arn" {
  value       = module.aurora.aurora_cluster_arn
  description = "ARN of the Aurora cluster. The global-database root uses it as the source of the global cluster."
}

output "cluster_resource_id" {
  value       = module.aurora.aurora_cluster_resource_id
  description = "Resource ID of the Aurora cluster, used in rds-db:connect policies"
}

output "databases" {
  value = {
    for k, d in var.databases : k => {
      database_name = d.database_name
      username      = d.username
      auth          = d.auth
      host          = module.aurora.aurora_endpoint
      port          = module.aurora.aurora_port
      # IAM authentication goes through the AWS JDBC wrapper; a password goes through the plain driver.
      jdbc_url = (d.auth == "iam"
        ? "jdbc:aws-wrapper:postgresql://${module.aurora.aurora_endpoint}:${module.aurora.aurora_port}/${d.database_name}?wrapperPlugins=iam"
      : "jdbc:postgresql://${module.aurora.aurora_endpoint}:${module.aurora.aurora_port}/${d.database_name}")
      password_secret_arn = d.auth == "password" ? aws_secretsmanager_secret.database[k].arn : ""
      connect_policy_arn  = d.auth == "iam" ? aws_iam_policy.rds_db_connect[d.username].arn : ""
    }
  }
  description = "Per further database: its connection settings. Components read their database from here: the JDBC URL, the role, the password secret (auth = password) or the connect policy to attach to the task role (auth = iam)."
}
