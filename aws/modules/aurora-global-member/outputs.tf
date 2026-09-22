output "cluster_identifier" {
  description = "Identifier of the regional Aurora cluster"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "ARN of the regional Aurora cluster"
  value       = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  description = "Immutable resource ID of the cluster, used to build rds-db:connect IAM policies"
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "endpoint" {
  description = "Writer endpoint of the regional cluster"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint of the regional cluster"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "instance_host_pattern" {
  description = <<-EOT
    Instance host pattern for the AWS Advanced JDBC Wrapper
    globalClusterInstanceHostPatterns parameter. The `?` placeholder is
    substituted with the instance identifier by the driver, which is how it
    enumerates the instances of every region after a global failover.
  EOT
  value       = "?.${replace(aws_rds_cluster.this.endpoint, "${aws_rds_cluster.this.cluster_identifier}.cluster-", "")}"
}

output "security_group_id" {
  description = "ID of the security group attached to the regional cluster"
  value       = aws_security_group.this.id
}
