output "public_url" {
  value       = "${var.public_base_url}${var.context_path}"
  description = "Browser-facing address of Camunda Hub. Register it as the login redirect in an OIDC provider that you run yourself: <public_url>/login-callback."
}

output "clusters" {
  value       = sort(keys(var.clusters))
  description = "IDs of the Orchestration Clusters that Camunda Hub is connected to"
}

output "service_name" {
  value       = module.camunda_hub.service_name
  description = "Name of the Camunda Hub ECS service"
}

output "clusters_config" {
  value       = jsondecode(local.clusters_json).camunda.modeler.clusters
  description = "The Orchestration Clusters as Camunda Hub is configured with them"
}
