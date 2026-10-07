output "service_name" {
  value       = aws_ecs_service.load_generator.name
  description = "The name of the load generator ECS service"
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.load_generator.arn
  description = "The ARN of the load generator task definition"
}

output "task_role_arn" {
  value       = aws_iam_role.ecs_task_role.arn
  description = "The ARN of the IAM role assumed by the load generator task"
}

output "log_group_name" {
  value       = local.log_group_name
  description = "The name of the CloudWatch log group the generator logs to. Its throughput lines are the signal this module exists to produce."
}

output "grpc_address" {
  value       = local.grpc_address
  description = "The gRPC address the generator drives load against"
}

output "rest_address" {
  value       = local.rest_address
  description = "The REST address the generator drives load against"
}
