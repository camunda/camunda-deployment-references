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
