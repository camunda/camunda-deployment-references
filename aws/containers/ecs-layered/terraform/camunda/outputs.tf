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
  value       = local.admin_user_password
  sensitive   = true
  description = "Password of the admin user in basic authentication mode, empty with OIDC. Also stored in Secrets Manager."
}

output "connectors_user_password" {
  value       = local.connectors_user_password
  sensitive   = true
  description = "Password of the connectors user in basic authentication mode, empty with OIDC. A second region takes it as connectors_user_password."
}

output "cluster_registration" {
  value = {
    version       = var.camunda_version
    rest_url      = "http://${module.orchestration_cluster.dns_a_record}:8080"
    grpc_url      = "grpc://${module.orchestration_cluster.dns_a_record}:26500"
    readiness_url = "http://${module.orchestration_cluster.dns_a_record}:9600/actuator/health/readiness"
  }
  description = "What Camunda Hub needs to connect to this cluster: add it to the clusters of the Camunda Hub layer. The addresses are service discovery names that resolve inside the VPC, and in a peered VPC through the Route 53 Resolver rules of the interconnect."
}
