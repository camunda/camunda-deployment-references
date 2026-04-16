################################################################
#              Region 0 — Networking & Compute                 #
################################################################

output "region_0_vpc_id" {
  value       = module.vpc_region_0.vpc_id
  description = "VPC ID for region 0"
}

output "region_0_private_subnets" {
  value       = module.vpc_region_0.private_subnets
  description = "Private subnet IDs for region 0"
}

output "region_0_ecs_cluster_id" {
  value       = aws_ecs_cluster.region_0.id
  description = "ECS cluster ID for region 0"
}

output "region_0_ecs_cluster_arn" {
  value       = aws_ecs_cluster.region_0.arn
  description = "ECS cluster ARN for region 0 (used by DB seed task)"
}

output "region_0_ecs_cluster_name" {
  value       = aws_ecs_cluster.region_0.name
  description = "ECS cluster name for region 0"
}

################################################################
#              Region 0 — Load Balancers                       #
################################################################

output "region_0_alb_endpoint" {
  value       = aws_lb.alb_region_0.dns_name
  description = "DNS name of the ALB in region 0 (HTTP/REST access)"
}

output "region_0_alb_http_webapp_listener_arn" {
  value       = aws_lb_listener.http_webapp_region_0.arn
  description = "ARN of the ALB HTTP webapp listener in region 0"
}

output "region_0_alb_http_management_listener_arn" {
  value       = aws_lb_listener.http_management_region_0.arn
  description = "ARN of the ALB HTTP management listener in region 0"
}

output "region_0_nlb_grpc_endpoint" {
  value       = aws_lb.nlb_grpc_region_0.dns_name
  description = "DNS name of the external NLB in region 0 (gRPC access)"
}

output "region_0_nlb_grpc_arn" {
  value       = aws_lb.nlb_grpc_region_0.arn
  description = "ARN of the external NLB in region 0"
}

output "region_0_nlb_raft_dns_name" {
  value       = aws_lb.nlb_raft_region_0.dns_name
  description = "DNS name of the internal Raft NLB in region 0 (used by region 1 brokers as contact point)"
}

output "region_0_nlb_raft_arn" {
  value       = aws_lb.nlb_raft_region_0.arn
  description = "ARN of the internal Raft NLB in region 0"
}

################################################################
#              Region 0 — IAM & Security                       #
################################################################

output "region_0_ecs_task_execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution_region_0.arn
  description = "ARN of the ECS task execution role in region 0"
}

output "region_0_ecs_task_execution_role_name" {
  value       = aws_iam_role.ecs_task_execution_region_0.name
  description = "Name of the ECS task execution role in region 0 (used to attach secrets policy)"
}

output "region_0_rds_db_connect_policy_arn" {
  value       = aws_iam_policy.rds_db_connect_region_0.arn
  description = "ARN of the RDS IAM auth policy for region 0 ECS tasks"
}

output "region_0_s3_backup_access_policy_arn" {
  value       = aws_iam_policy.s3_backup_access_region_0.arn
  description = "ARN of the S3 backup access policy for region 0"
}

output "region_0_camunda_ports_sg_id" {
  value       = aws_security_group.camunda_ports_region_0.id
  description = "Security group ID for Camunda ports in region 0"
}

output "region_0_package_80_443_sg_id" {
  value       = aws_security_group.package_80_443_region_0.id
  description = "Security group ID for outbound HTTP/HTTPS in region 0"
}

output "region_0_efs_sg_id" {
  value       = aws_security_group.efs_region_0.id
  description = "Security group ID for EFS in region 0"
}

output "region_0_secrets_kms_key_arn" {
  value       = local.secrets_kms_key_arn_region_0
  description = "KMS key ARN used for Secrets Manager in region 0"
}

output "region_0_backup_bucket_name" {
  value       = aws_s3_bucket.backup_region_0.id
  description = "Name of the S3 backup bucket in region 0"
}

################################################################
#              Region 1 — Networking & Compute                 #
################################################################

output "region_1_vpc_id" {
  value       = module.vpc_region_1.vpc_id
  description = "VPC ID for region 1"
}

output "region_1_private_subnets" {
  value       = module.vpc_region_1.private_subnets
  description = "Private subnet IDs for region 1"
}

output "region_1_ecs_cluster_id" {
  value       = aws_ecs_cluster.region_1.id
  description = "ECS cluster ID for region 1"
}

output "region_1_ecs_cluster_name" {
  value       = aws_ecs_cluster.region_1.name
  description = "ECS cluster name for region 1"
}

################################################################
#              Region 1 — Load Balancers                       #
################################################################

output "region_1_alb_endpoint" {
  value       = aws_lb.alb_region_1.dns_name
  description = "DNS name of the ALB in region 1 (HTTP/REST access)"
}

output "region_1_alb_http_webapp_listener_arn" {
  value       = aws_lb_listener.http_webapp_region_1.arn
  description = "ARN of the ALB HTTP webapp listener in region 1"
}

output "region_1_alb_http_management_listener_arn" {
  value       = aws_lb_listener.http_management_region_1.arn
  description = "ARN of the ALB HTTP management listener in region 1"
}

output "region_1_nlb_grpc_endpoint" {
  value       = aws_lb.nlb_grpc_region_1.dns_name
  description = "DNS name of the external NLB in region 1 (gRPC access)"
}

output "region_1_nlb_grpc_arn" {
  value       = aws_lb.nlb_grpc_region_1.arn
  description = "ARN of the external NLB in region 1"
}

output "region_1_nlb_raft_dns_name" {
  value       = aws_lb.nlb_raft_region_1.dns_name
  description = "DNS name of the internal Raft NLB in region 1 (used by region 0 brokers as contact point)"
}

output "region_1_nlb_raft_arn" {
  value       = aws_lb.nlb_raft_region_1.arn
  description = "ARN of the internal Raft NLB in region 1"
}

################################################################
#              Region 1 — IAM & Security                       #
################################################################

output "region_1_ecs_task_execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution_region_1.arn
  description = "ARN of the ECS task execution role in region 1"
}

output "region_1_ecs_task_execution_role_name" {
  value       = aws_iam_role.ecs_task_execution_region_1.name
  description = "Name of the ECS task execution role in region 1 (used to attach secrets policy)"
}

output "region_1_rds_db_connect_policy_arn" {
  value       = aws_iam_policy.rds_db_connect_region_1.arn
  description = "ARN of the RDS IAM auth policy for region 1 ECS tasks"
}

output "region_1_s3_backup_access_policy_arn" {
  value       = aws_iam_policy.s3_backup_access_region_1.arn
  description = "ARN of the S3 backup access policy for region 1"
}

output "region_1_camunda_ports_sg_id" {
  value       = aws_security_group.camunda_ports_region_1.id
  description = "Security group ID for Camunda ports in region 1"
}

output "region_1_package_80_443_sg_id" {
  value       = aws_security_group.package_80_443_region_1.id
  description = "Security group ID for outbound HTTP/HTTPS in region 1"
}

output "region_1_efs_sg_id" {
  value       = aws_security_group.efs_region_1.id
  description = "Security group ID for EFS in region 1"
}

output "region_1_secrets_kms_key_arn" {
  value       = local.secrets_kms_key_arn_region_1
  description = "KMS key ARN used for Secrets Manager in region 1"
}

output "region_1_backup_bucket_name" {
  value       = aws_s3_bucket.backup_region_1.id
  description = "Name of the S3 backup bucket in region 1"
}

################################################################
#                        Aurora Outputs                        #
################################################################

output "aurora_global_cluster_id" {
  value       = module.aurora_global.global_cluster_id
  description = "ID of the Aurora Global Database cluster"
}

output "aurora_primary_cluster_identifier" {
  value       = module.aurora_global.primary_cluster_identifier
  description = "Cluster identifier of the Aurora primary cluster (region 0)"
}

output "aurora_secondary_cluster_identifier" {
  value       = module.aurora_global.secondary_cluster_identifier
  description = "Cluster identifier of the Aurora secondary cluster (region 1)"
}

output "aurora_primary_cluster_endpoint" {
  value       = module.aurora_global.primary_cluster_endpoint
  description = "Writer endpoint of the Aurora Global DB primary cluster (region 0)"
}

output "aurora_secondary_cluster_endpoint" {
  value       = module.aurora_global.secondary_cluster_endpoint
  description = "Endpoint of the Aurora Global DB secondary cluster (region 1)"
}

output "aurora_primary_cluster_resource_id" {
  value       = module.aurora_global.primary_cluster_resource_id
  description = "Resource ID of the Aurora primary cluster (used for IAM auth ARNs)"
}

output "aurora_secondary_cluster_resource_id" {
  value       = module.aurora_global.secondary_cluster_resource_id
  description = "Resource ID of the Aurora secondary cluster (used for IAM auth ARNs)"
}

################################################################
#                     DB Admin Secret                          #
################################################################

output "db_admin_secret_arn" {
  value       = aws_secretsmanager_secret.db_admin_password_region_0.arn
  description = "ARN of the Aurora admin password secret in region 0 (read by the DB seed task)"
}

output "db_admin_password" {
  value       = local.db_admin_password_effective
  sensitive   = true
  description = "The Aurora PostgreSQL admin password"
}
