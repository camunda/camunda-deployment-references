output "dns_a_record" {
  value       = "prometheus.${var.prefix}.service.local"
  description = "The private DNS name the Prometheus service registers in Cloud Map"
}

output "prometheus_endpoint" {
  value       = "http://prometheus.${var.prefix}.service.local:${var.prometheus_port}"
  description = "The in-VPC base URL of the Prometheus server"
}

output "prometheus_port" {
  value       = var.prometheus_port
  description = "The port Prometheus listens on"
}

output "service_name" {
  value       = aws_ecs_service.prometheus.name
  description = "The name of the Prometheus ECS service"
}

output "task_role_arn" {
  value       = aws_iam_role.ecs_task_role.arn
  description = "The ARN of the IAM role assumed by the Prometheus task"
}

output "log_group_name" {
  value       = local.log_group_name
  description = "The name of the CloudWatch log group the monitoring task logs to"
}

output "target_group_arn" {
  value       = one(aws_lb_target_group.prometheus[*].arn)
  description = "The ARN of the ALB target group, when Prometheus is exposed through a listener"
}
