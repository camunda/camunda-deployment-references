output "grpc_service_connect" {
  value       = module.orchestration_cluster.grpc_service_connect
  description = "Service Connect name of the gRPC endpoint, reachable inside the ECS cluster"
}

output "rest_service_connect" {
  value       = module.orchestration_cluster.rest_service_connect
  description = "Service Connect name of the REST endpoint, reachable inside the ECS cluster"
}

output "lease_bucket_name" {
  value       = module.orchestration_cluster.s3_bucket_name
  description = "Node ID lease bucket used by this zone"
}

output "log_group_name" {
  value       = module.orchestration_cluster.log_group_name
  description = "CloudWatch log group of the Orchestration Cluster"
}

output "admin_user_password" {
  value       = try(random_password.admin_user[0].result, "")
  sensitive   = true
  description = "Password of the admin user in basic authentication mode, empty with OIDC. Also stored in Secrets Manager."
}
