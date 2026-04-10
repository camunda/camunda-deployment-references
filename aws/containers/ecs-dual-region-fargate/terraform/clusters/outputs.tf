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

################################################################
#                        Aurora Outputs                        #
################################################################

output "aurora_global_cluster_id" {
  value       = module.aurora_global.global_cluster_id
  description = "The ID of the Aurora Global Database cluster"
}

output "aurora_primary_endpoint" {
  value       = module.aurora_global.primary_cluster_endpoint
  description = "The writer endpoint of the Aurora Global DB primary cluster (region 0)"
}

output "aurora_secondary_endpoint" {
  value       = module.aurora_global.secondary_cluster_endpoint
  description = "The endpoint of the Aurora Global DB secondary cluster (region 1)"
}

################################################################
#                        Shared Outputs                        #
################################################################

output "admin_user_password" {
  value       = random_password.admin_user_password.result
  description = "The admin password for Camunda. Easy access purposes, saved in Secrets Manager."
  sensitive   = true
}
