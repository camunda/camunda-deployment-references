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
