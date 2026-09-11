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
  description = <<-EOT
    DEPRECATED — prefer composing the URL from the jdbc_* component outputs below.

    A fully assembled AWS Advanced JDBC Wrapper URL for the Aurora Global writer
    (engine-aware subprotocol and port, iam when enabled + failover plugins,
    globalClusterInstanceHostPatterns, TLS pinned). Kept for backward
    compatibility, but building the URL here forces a change to any connection
    property — a timeout, a pool setting — through this module and a redeploy of
    the infrastructure layer. Consumers should instead read jdbc_subprotocol,
    global_cluster_endpoint, db_port, database_name and jdbc_url_parameters, and
    assemble the URL where the application is configured. This output will be
    removed in a future major.
  EOT
}

################################################################
#   JDBC URL components (compose the URL in the app layer)     #
################################################################

output "jdbc_subprotocol" {
  value       = local.jdbc_subprotocol
  description = "JDBC subprotocol for the selected engine ('postgresql' or 'mysql'), i.e. the segment after 'jdbc:aws-wrapper:'."
}

output "database_name" {
  value       = var.database_name
  description = "The database created on the cluster; the path segment of the JDBC URL."
}

output "jdbc_url_parameters" {
  value       = local.jdbc_url_parameters
  description = "Every query parameter for the JDBC URL, as a map: wrapperPlugins ('failover', plus 'iam' and 'initialConnection' when iam_auth_enabled, plus any extra_wrapper_plugins), globalClusterInstanceHostPatterns, the engine's TLS key (sslmode=require for PostgreSQL, sslMode=REQUIRED for MySQL — pinned rather than left to the driver default, which permits a plaintext downgrade), and any extra_url_parameters. Render it as '?' plus '&'-joined 'key=value' pairs; no entry carries a separator of its own."
}
