output "keycloak_service_connect" {
  description = "Service Connect DNS name for Keycloak (reachable at http://<this>:18080/auth within the ECS cluster)."
  value       = aws_ecs_service.keycloak.service_connect_configuration[0].service[0].discovery_name
}
