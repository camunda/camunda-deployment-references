################################################################
#                        Region 0 Outputs                      #
################################################################

output "region_0_alb_endpoint" {
  value       = local.infra.region_0_alb_endpoint
  description = "The DNS name of the ALB in region 0 (HTTP/REST access)"
}

output "region_0_nlb_grpc_endpoint" {
  value       = local.infra.region_0_nlb_grpc_endpoint
  description = "The DNS name of the external NLB in region 0 (gRPC access)"
}

output "region_0_ecs_cluster_name" {
  value       = local.infra.region_0_ecs_cluster_name
  description = "The name of the ECS cluster in region 0"
}

output "region_0_log_group_name" {
  value       = module.orchestration_cluster_region_0.log_group_name
  description = "CloudWatch log group for the orchestration cluster in region 0"
}

output "region_0_backup_bucket_name" {
  value       = local.infra.region_0_backup_bucket_name
  description = "Name of the S3 backup bucket in region 0"
}

################################################################
#                        Region 1 Outputs                      #
################################################################

output "region_1_alb_endpoint" {
  value       = local.infra.region_1_alb_endpoint
  description = "The DNS name of the ALB in region 1 (HTTP/REST access)"
}

output "region_1_nlb_grpc_endpoint" {
  value       = local.infra.region_1_nlb_grpc_endpoint
  description = "The DNS name of the external NLB in region 1 (gRPC access)"
}

output "region_1_ecs_cluster_name" {
  value       = local.infra.region_1_ecs_cluster_name
  description = "The name of the ECS cluster in region 1"
}

output "region_1_log_group_name" {
  value       = module.orchestration_cluster_region_1.log_group_name
  description = "CloudWatch log group for the orchestration cluster in region 1"
}

output "region_1_backup_bucket_name" {
  value       = local.infra.region_1_backup_bucket_name
  description = "Name of the S3 backup bucket in region 1"
}

################################################################
#                        Aurora Outputs                        #
################################################################

output "aurora_global_cluster_id" {
  value       = local.infra.aurora_global_cluster_id
  description = "The ID of the Aurora Global Database cluster"
}

output "aurora_primary_endpoint" {
  value       = local.infra.aurora_primary_cluster_endpoint
  description = "The writer endpoint of the Aurora Global DB primary cluster (region 0)"
}

output "aurora_secondary_endpoint" {
  value       = local.infra.aurora_secondary_cluster_endpoint
  description = "The endpoint of the Aurora Global DB secondary cluster (region 1)"
}

################################################################
#                        Shared Outputs                        #
################################################################

output "admin_user_password" {
  value       = random_password.admin_user_password.result
  description = "The Camunda admin user password. Stored in Secrets Manager in each region."
  sensitive   = true
}

output "db_admin_password" {
  value       = local.infra.db_admin_password
  description = "The Aurora PostgreSQL admin password. Stored in Secrets Manager in region 0."
  sensitive   = true
}
