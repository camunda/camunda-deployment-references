output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.app_rg.name
}

output "aks_cluster_id" {
  description = "ID of the deployed AKS cluster"
  value       = module.aks.aks_cluster_id
}

output "aks_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = module.aks.aks_fqdn
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.aks_cluster_name
}

## output locals to be able to retrieve all at once for DB setup, preventing lock storm

output "camunda_database_identity" {
  value = local.camunda_database_identity
}

output "camunda_identity_db_username" {
  value = local.camunda_identity_db_username
}

output "camunda_identity_db_password" {
  value     = local.camunda_identity_db_password
  sensitive = true
}

output "camunda_database_webmodeler" {
  value = local.camunda_database_webmodeler
}

output "camunda_webmodeler_db_username" {
  value = local.camunda_webmodeler_db_username
}

output "camunda_webmodeler_db_password" {
  value     = local.camunda_webmodeler_db_password
  sensitive = true
}

# RDBMS secondary storage: orchestration database outputs
output "camunda_database_orchestration" {
  value = local.camunda_database_orchestration
}

output "camunda_orchestration_db_username" {
  value = local.camunda_orchestration_db_username
}

output "camunda_orchestration_db_password" {
  value     = local.camunda_orchestration_db_password
  sensitive = true
}

output "postgres_version" {
  description = "PostgreSQL major version"
  value       = var.postgres_version
}
