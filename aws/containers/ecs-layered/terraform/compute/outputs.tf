output "ecs_cluster_id" {
  value       = aws_ecs_cluster.this.id
  description = "ID of the ECS cluster"
}

output "ecs_cluster_arn" {
  value       = aws_ecs_cluster.this.arn
  description = "ARN of the ECS cluster"
}

output "task_execution_role_arn" {
  value       = aws_iam_role.task_execution.arn
  description = "ARN of the ECS task execution role"
}

output "task_execution_role_name" {
  value       = aws_iam_role.task_execution.name
  description = "Name of the ECS task execution role. Layers that create secrets attach a read policy to it."
}

output "secrets_kms_key_arn" {
  value       = local.secrets_kms_key_arn
  description = "KMS key that encrypts the Secrets Manager secrets of every layer"
}

output "registry_credentials_arn" {
  value       = join("", aws_secretsmanager_secret.registry_credentials[*].arn)
  description = "ARN of the registry credentials secret, empty when no registry credentials are configured"
}

output "camunda_ports_security_group_id" {
  value       = aws_security_group.camunda_ports_within_vpc.id
  description = "Security group that opens the Camunda ports inside the VPC. Attach it to every service and to the load balancers."
}

output "egress_security_group_id" {
  value       = aws_security_group.egress_80_443.id
  description = "Security group that allows outbound HTTP and HTTPS"
}

output "efs_security_group_id" {
  value       = aws_security_group.efs.id
  description = "Security group of the EFS file systems"
}

output "service_connect_namespace_arn" {
  value       = aws_service_discovery_http_namespace.service_connect.arn
  description = "Service Connect namespace for the components that run outside an Orchestration Cluster"
}

output "components_log_group_name" {
  value       = aws_cloudwatch_log_group.components.name
  description = "CloudWatch log group for the components that run outside an Orchestration Cluster"
}
