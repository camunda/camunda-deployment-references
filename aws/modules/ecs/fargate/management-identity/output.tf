output "identity_service_connect" {
  description = "Service Connect DNS name for Management Identity (reachable at this name on port 8084 within the ECS cluster)."
  value       = aws_ecs_service.management_identity.service_connect_configuration[0].service[0].discovery_name
}
