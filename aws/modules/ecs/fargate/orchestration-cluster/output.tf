output "s3_bucket_name" {
  value       = aws_s3_bucket.main.id
  description = "The name of the S3 bucket"
}

output "dns_a_record" {
  value = "orchestration-cluster.${var.prefix}.service.local"
}

output "s2s_cloudmap_namespace" {
  value       = aws_service_discovery_http_namespace.service_connect.arn
  description = "The ARN of the Service Connect namespace for service-to-service communication"
}

output "grpc_service_connect" {
  value       = aws_ecs_service.orchestration_cluster.service_connect_configuration[0].service[0].discovery_name
  description = "The Service Connect discovery name for the orchestration cluster ECS service targeting gRPC"
}

output "rest_service_connect" {
  value       = aws_ecs_service.orchestration_cluster.service_connect_configuration[0].service[2].discovery_name
  description = "The Service Connect discovery name for the orchestration cluster ECS service targeting REST"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.orchestration_cluster_log_group.name
  description = "The name of the CloudWatch log group for the orchestration cluster"
}
