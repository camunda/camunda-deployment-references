output "alb_endpoint" {
  value       = join("", aws_lb.main[*].dns_name)
  description = "(Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp."
}

output "nlb_endpoint" {
  value       = join("", aws_lb.grpc[*].dns_name)
  description = "(Optional) The DNS name of the Network Load Balancer (NLB) to access the Camunda Core."
}
output "admin_user_password" {
  value       = random_password.admin_user_password.result
  description = "The admin password for Camunda. Easy access purposes, saved in Secrets Manager."
  sensitive   = true
}

################################################################
#                      Load test overlay                       #
################################################################

output "prometheus_endpoint" {
  value       = one(module.monitoring[*].prometheus_endpoint)
  description = "In-VPC base URL of the load test Prometheus, or null when enable_load_tests is false."
}

output "load_generator_log_group" {
  value       = one(module.load_generator[*].log_group_name)
  description = "CloudWatch log group carrying the load generator's throughput lines, or null when enable_load_tests is false."
}

output "load_generator_target" {
  value       = one(module.load_generator[*].grpc_address) != null ? module.orchestration_cluster.dns_a_record : null
  description = "The Orchestration Cluster the load generator drives, or null when enable_load_tests is false."
}
