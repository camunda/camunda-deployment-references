################################################################
#                        App Outputs                           #
################################################################

output "region_0_alb_endpoint" {
  value       = local.infra.region_0_alb_endpoint
  description = "The DNS name of the ALB in region 0 (HTTP/REST access)"
}

output "region_1_alb_endpoint" {
  value       = local.infra.region_1_alb_endpoint
  description = "The DNS name of the ALB in region 1 (HTTP/REST access)"
}

output "region_0_nlb_grpc_endpoint" {
  value       = local.infra.region_0_nlb_grpc_endpoint
  description = "The DNS name of the external NLB in region 0 (gRPC access)"
}

output "region_1_nlb_grpc_endpoint" {
  value       = local.infra.region_1_nlb_grpc_endpoint
  description = "The DNS name of the external NLB in region 1 (gRPC access)"
}

output "region_0_log_group_name" {
  value       = module.orchestration_cluster_region_0.log_group_name
  description = "CloudWatch log group for the orchestration cluster in region 0"
}

output "region_1_log_group_name" {
  value       = module.orchestration_cluster_region_1.log_group_name
  description = "CloudWatch log group for the orchestration cluster in region 1"
}

output "admin_user_password" {
  value       = local.infra.admin_user_password
  description = "The admin password for Camunda"
  sensitive   = true
}
