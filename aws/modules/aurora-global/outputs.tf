output "global_cluster_id" {
  value       = aws_rds_global_cluster.this.id
  description = "The ID of the Aurora Global Database cluster"
}

output "global_cluster_resource_id" {
  value       = aws_rds_global_cluster.this.global_cluster_resource_id
  description = "The resource ID of the Aurora Global Database cluster (used for IAM auth)"
}

output "global_cluster_arn" {
  value       = aws_rds_global_cluster.this.arn
  description = "The ARN of the Aurora Global Database cluster"
}

output "global_cluster_endpoint" {
  value       = aws_rds_global_cluster.this.endpoint
  description = "The writer endpoint for the Aurora Global Database cluster. This endpoint always points to the writer DB instance in the current primary cluster."
}

output "primary_cluster_endpoint" {
  value       = aws_rds_cluster.primary.endpoint
  description = "The writer endpoint of the primary Aurora cluster"
}

output "primary_cluster_reader_endpoint" {
  value       = aws_rds_cluster.primary.reader_endpoint
  description = "The reader endpoint of the primary Aurora cluster"
}

output "primary_cluster_identifier" {
  value       = aws_rds_cluster.primary.cluster_identifier
  description = "The identifier of the primary Aurora cluster"
}

output "primary_cluster_resource_id" {
  value       = aws_rds_cluster.primary.cluster_resource_id
  description = "The resource ID of the primary Aurora cluster (used for IAM auth)"
}

output "secondary_cluster_endpoint" {
  value       = aws_rds_cluster.secondary.endpoint
  description = "The endpoint of the secondary Aurora cluster"
}

output "secondary_cluster_reader_endpoint" {
  value       = aws_rds_cluster.secondary.reader_endpoint
  description = "The reader endpoint of the secondary Aurora cluster"
}

output "secondary_cluster_identifier" {
  value       = aws_rds_cluster.secondary.cluster_identifier
  description = "The identifier of the secondary Aurora cluster"
}

output "secondary_cluster_resource_id" {
  value       = aws_rds_cluster.secondary.cluster_resource_id
  description = "The resource ID of the secondary Aurora cluster (used for IAM auth)"
}

output "db_port" {
  value       = local.db_port
  description = "The database port for the selected engine (5432 for PostgreSQL, 3306 for MySQL)."
}

output "jdbc_url" {
  value       = local.jdbc_url
  description = "Ready-to-use AWS Advanced JDBC Wrapper URL for the Aurora Global writer, engine-aware, with iam (when enabled) + failover plugins and globalClusterInstanceHostPatterns."
}

output "jdbc_instance_host_patterns" {
  value       = local.jdbc_instance_host_patterns
  description = "Comma-separated globalClusterInstanceHostPatterns for the AWS JDBC Wrapper failover plugin (primary,secondary)."
}
