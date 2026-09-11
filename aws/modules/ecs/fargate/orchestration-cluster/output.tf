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

locals {
  # Index the Service Connect entries by port_name rather than addressing them
  # positionally. The list order is an implementation detail of the service block, so
  # inserting or reordering an entry would silently repoint these outputs at the wrong
  # port while still planning and applying cleanly.
  service_connect_discovery_names = {
    for service in aws_ecs_service.orchestration_cluster.service_connect_configuration[0].service :
    service.port_name => service.discovery_name
  }
}

output "grpc_service_connect" {
  value       = local.service_connect_discovery_names["grpc"]
  description = "The Service Connect discovery name for the orchestration cluster ECS service targeting gRPC"
}

output "rest_service_connect" {
  value       = local.service_connect_discovery_names["rest"]
  description = "The Service Connect discovery name for the orchestration cluster ECS service targeting REST"
}

output "management_service_connect" {
  value       = local.service_connect_discovery_names["management"]
  description = "The Service Connect discovery name for the orchestration cluster management/actuator port (reachable at http://<this>:9600 within the ECS cluster)"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.orchestration_cluster_log_group.name
  description = "The name of the CloudWatch log group for the orchestration cluster"
}
