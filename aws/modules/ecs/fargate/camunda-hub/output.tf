output "service_name" {
  description = "The name of the Camunda Hub ECS service"
  value       = aws_ecs_service.camunda_hub.name
}

output "restapi_target_group_arn" {
  description = "The ARN of the restapi ALB target group"
  value       = aws_lb_target_group.restapi.arn
}

output "websockets_target_group_arn" {
  description = "The ARN of the websockets ALB target group"
  value       = aws_lb_target_group.websockets.arn
}
