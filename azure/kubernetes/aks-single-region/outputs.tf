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

output "postgres_fqdn" {
  description = "The fully qualified domain name of the PostgreSQL Flexible Server"
  value       = module.postgres_db.fqdn
}

output "postgres_admin_username" {
  description = "PostgreSQL admin user"
  value       = local.db_admin_username
}

output "postgres_admin_password" {
  description = "PostgreSQL admin password"
  value       = local.db_admin_password
  sensitive   = true
}
