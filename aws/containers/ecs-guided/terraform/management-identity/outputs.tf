output "internal_url" {
  value       = "http://${module.management_identity.identity_service_connect}:8084${var.context_path}"
  description = "Address of Management Identity inside the ECS cluster, with its context path. Camunda Hub calls it."
}

output "public_url" {
  value       = local.identity_base_public
  description = "Browser-facing address of Management Identity"
}

output "hub_authorization_enabled" {
  value       = local.hub_authorization_enabled
  description = "Whether the roles Camunda Hub needs are declared. The Camunda Hub stage requires true."
}

output "identity_service_connect" {
  value       = module.management_identity.identity_service_connect
  description = "Service Connect name of Management Identity"
}

output "authorization" {
  value       = local.hub_authorization_enabled ? jsondecode(local.authorization_json) : null
  description = "The authorization model that Management Identity is seeded with (presets and mapping rule), or null when enable_hub_authorization is false"
}
