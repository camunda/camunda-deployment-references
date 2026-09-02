################################################################
#                        Region Configuration                  #
################################################################

output "region_0" {
  value = var.region_0
}

output "region_1" {
  value = var.region_1
}

output "cluster_name" {
  value = var.cluster_name
}

output "secondary_storage_type" {
  value = var.secondary_storage_type
}

################################################################
#                        VPC Outputs (re-exported)             #
#                                                                #
# Re-exported from terraform/vpc/ remote state so that app/     #
# consumers don't need to read a second state. Old names are    #
# preserved for back-compat — internally these read from        #
# local.vpc which is data.terraform_remote_state.vpc.outputs.   #
################################################################

output "vpc_region_0_id" {
  value = local.vpc.region_0_vpc_id
}

output "vpc_region_0_private_subnets" {
  value = local.vpc.region_0_private_subnet_ids
}

output "vpc_region_1_id" {
  value = local.vpc.region_1_vpc_id
}

output "vpc_region_1_private_subnets" {
  value = local.vpc.region_1_private_subnet_ids
}

################################################################
#                        ECS Cluster Outputs                   #
################################################################

output "ecs_cluster_region_0_id" {
  value = aws_ecs_cluster.region_0.id
}

output "ecs_cluster_region_1_id" {
  value = aws_ecs_cluster.region_1.id
}

################################################################
#                        Load Balancer Outputs                 #
################################################################

output "region_0_alb_endpoint" {
  value       = aws_lb.alb_region_0.dns_name
  description = "The DNS name of the ALB in region 0 (HTTP/REST access)"
}

output "region_1_alb_endpoint" {
  value       = aws_lb.alb_region_1.dns_name
  description = "The DNS name of the ALB in region 1 (HTTP/REST access)"
}

output "alb_listener_http_webapp_region_0_arn" {
  value = aws_lb_listener.http_webapp_region_0.arn
}

output "alb_listener_http_webapp_region_1_arn" {
  value = aws_lb_listener.http_webapp_region_1.arn
}

output "alb_listener_http_management_region_0_arn" {
  value = aws_lb_listener.http_management_region_0.arn
}

output "alb_listener_http_management_region_1_arn" {
  value = aws_lb_listener.http_management_region_1.arn
}

output "nlb_grpc_region_0_arn" {
  value = aws_lb.nlb_grpc_region_0.arn
}

output "nlb_grpc_region_1_arn" {
  value = aws_lb.nlb_grpc_region_1.arn
}

output "nlb_raft_region_0_arn" {
  value = aws_lb.nlb_raft_region_0.arn
}

output "nlb_raft_region_1_arn" {
  value = aws_lb.nlb_raft_region_1.arn
}

output "region_0_nlb_raft_endpoint" {
  value       = aws_lb.nlb_raft_region_0.dns_name
  description = "The DNS name of the internal NLB in region 0 (cross-region Raft port 26502)"
}

output "region_1_nlb_raft_endpoint" {
  value       = aws_lb.nlb_raft_region_1.dns_name
  description = "The DNS name of the internal NLB in region 1 (cross-region Raft port 26502)"
}

output "region_0_nlb_grpc_endpoint" {
  value       = aws_lb.nlb_grpc_region_0.dns_name
  description = "The DNS name of the external NLB in region 0 (gRPC access)"
}

output "region_1_nlb_grpc_endpoint" {
  value       = aws_lb.nlb_grpc_region_1.dns_name
  description = "The DNS name of the external NLB in region 1 (gRPC access)"
}

################################################################
#                        Security Group Outputs                #
################################################################

output "sg_camunda_ports_region_0_id" {
  value = aws_security_group.camunda_ports_region_0.id
}

output "sg_camunda_ports_region_1_id" {
  value = aws_security_group.camunda_ports_region_1.id
}

output "sg_package_80_443_region_0_id" {
  value = aws_security_group.package_80_443_region_0.id
}

output "sg_package_80_443_region_1_id" {
  value = aws_security_group.package_80_443_region_1.id
}

output "sg_efs_region_0_id" {
  value = aws_security_group.efs_region_0.id
}

output "sg_efs_region_1_id" {
  value = aws_security_group.efs_region_1.id
}

################################################################
#                        IAM Outputs                           #
################################################################

output "ecs_task_execution_role_region_0_arn" {
  value = aws_iam_role.ecs_task_execution_region_0.arn
}

output "ecs_task_execution_role_region_1_arn" {
  value = aws_iam_role.ecs_task_execution_region_1.arn
}

output "rds_db_connect_policy_region_0_arn" {
  value = var.secondary_storage_type == "rdbms" ? aws_iam_policy.rds_db_connect_region_0[0].arn : null
}

output "rds_db_connect_policy_region_1_arn" {
  value = var.secondary_storage_type == "rdbms" ? aws_iam_policy.rds_db_connect_region_1[0].arn : null
}

output "s3_backup_access_policy_region_0_arn" {
  value = aws_iam_policy.s3_backup_access_region_0.arn
}


################################################################
#                        Secrets Outputs                       #
################################################################

output "admin_user_password" {
  value       = random_password.admin_user_password.result
  description = "The admin password for Camunda"
  sensitive   = true
}

output "admin_user_password_secret_region_0_arn" {
  value = aws_secretsmanager_secret.admin_user_password_region_0.arn
}

output "admin_user_password_secret_region_1_arn" {
  value = aws_secretsmanager_secret.admin_user_password_region_1.arn
}

output "connectors_password_secret_region_0_arn" {
  value = aws_secretsmanager_secret.connectors_password_region_0.arn
}

output "connectors_password_secret_region_1_arn" {
  value = aws_secretsmanager_secret.connectors_password_region_1.arn
}

output "registry_credentials_region_0_arn" {
  value = var.registry_username != "" ? aws_secretsmanager_secret.registry_credentials_region_0[0].arn : ""
}

output "registry_credentials_region_1_arn" {
  value = var.registry_username != "" ? aws_secretsmanager_secret.registry_credentials_region_1[0].arn : ""
}

################################################################
#                        Aurora Outputs                        #
################################################################

output "aurora_global_cluster_id" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].global_cluster_id : null
  description = "The ID of the Aurora Global Database cluster"
}

output "aurora_global_writer_endpoint" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].global_cluster_endpoint : null
  description = "The global writer endpoint of the Aurora Global DB. Always routes to the current writer across regions after failover."
}

output "aurora_primary_cluster_endpoint" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].primary_cluster_endpoint : null
  description = "The regional writer endpoint of the primary Aurora cluster (region 0). Used to derive globalClusterInstanceHostPatterns for the AWS JDBC wrapper."
}

output "aurora_primary_cluster_identifier" {
  value = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].primary_cluster_identifier : null
}

output "aurora_secondary_cluster_identifier" {
  value = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].secondary_cluster_identifier : null
}

output "aurora_secondary_cluster_endpoint" {
  value       = var.secondary_storage_type == "rdbms" ? module.aurora_global[0].secondary_cluster_endpoint : null
  description = "The regional endpoint of the secondary Aurora cluster (region 1). Used to derive globalClusterInstanceHostPatterns for the AWS JDBC wrapper."
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
#                        S3 Outputs                            #
################################################################

output "backup_bucket_region_0_name" {
  value = aws_s3_bucket.backup_region_0.bucket
}


output "s3_force_destroy" {
  value = var.s3_force_destroy
}

output "db_name" {
  value = var.db_name
}

output "db_admin_username" {
  value     = var.db_admin_username
  sensitive = true
}
