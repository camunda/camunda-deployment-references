################################################################
#                        Region 0 Outputs                      #
################################################################

output "region_0_alb_endpoint" {
  value       = aws_lb.alb_region_0.dns_name
  description = "The DNS name of the ALB in region 0 (HTTP/REST access)"
}

output "region_0_nlb_grpc_endpoint" {
  value       = aws_lb.nlb_grpc_region_0.dns_name
  description = "The DNS name of the external NLB in region 0 (gRPC access)"
}

output "region_0_nlb_raft_endpoint" {
  value       = aws_lb.nlb_raft_region_0.dns_name
  description = "The DNS name of the internal NLB in region 0 (cross-region Raft)"
}

output "region_0_ecs_cluster_name" {
  value       = aws_ecs_cluster.region_0.name
  description = "The name of the ECS cluster in region 0"
}

output "region_0_log_group_name" {
  value       = module.orchestration_cluster_region_0.log_group_name
  description = "CloudWatch log group for the orchestration cluster in region 0"
}

output "region_0_backup_bucket_name" {
  value       = aws_s3_bucket.backup_region_0.id
  description = "Name of the S3 backup bucket in region 0"
}

################################################################
#                        Region 1 Outputs                      #
################################################################

output "region_1_alb_endpoint" {
  value       = aws_lb.alb_region_1.dns_name
  description = "The DNS name of the ALB in region 1 (HTTP/REST access)"
}

output "region_1_nlb_grpc_endpoint" {
  value       = aws_lb.nlb_grpc_region_1.dns_name
  description = "The DNS name of the external NLB in region 1 (gRPC access)"
}

output "region_1_nlb_raft_endpoint" {
  value       = aws_lb.nlb_raft_region_1.dns_name
  description = "The DNS name of the internal NLB in region 1 (cross-region Raft)"
}

output "region_1_ecs_cluster_name" {
  value       = aws_ecs_cluster.region_1.name
  description = "The name of the ECS cluster in region 1"
}

output "region_1_log_group_name" {
  value       = module.orchestration_cluster_region_1.log_group_name
  description = "CloudWatch log group for the orchestration cluster in region 1"
}

output "region_1_backup_bucket_name" {
  value       = aws_s3_bucket.backup_region_1.id
  description = "Name of the S3 backup bucket in region 1"
}

################################################################
#                        Aurora Outputs                        #
################################################################

output "aurora_global_cluster_id" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].global_cluster_id : null
  description = "The ID of the Aurora Global Database cluster"
}

output "aurora_primary_endpoint" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].primary_cluster_endpoint : null
  description = "The writer endpoint of the Aurora Global DB primary cluster (region 0)"
}

output "aurora_secondary_endpoint" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].secondary_cluster_endpoint : null
  description = "The endpoint of the Aurora Global DB secondary cluster (region 1)"
}

output "aurora_primary_cluster_identifier" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].primary_cluster_identifier : null
  description = "The cluster identifier of the Aurora primary cluster (region 0)"
}

output "aurora_secondary_cluster_identifier" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].secondary_cluster_identifier : null
  description = "The cluster identifier of the Aurora secondary cluster (region 1)"
}

################################################################
#                     OpenSearch Outputs                        #
################################################################

output "opensearch_region_0_endpoint" {
  value       = var.secondary_storage_type == "opensearch" ? module.opensearch_region_0[0].opensearch_domain_endpoint : null
  description = "The endpoint of the OpenSearch domain in region 0"
}

output "opensearch_region_1_endpoint" {
  value       = var.secondary_storage_type == "opensearch" ? module.opensearch_region_1[0].opensearch_domain_endpoint : null
  description = "The endpoint of the OpenSearch domain in region 1"
}

################################################################
#                        Shared Outputs                        #
################################################################

output "admin_user_password" {
  value       = random_password.admin_user_password.result
  description = "The admin password for Camunda. Easy access purposes, saved in Secrets Manager."
  sensitive   = true
}
