output "aks_subnet_id" {
  description = "ID of the subnet where AKS is deployed"
  value       = azurerm_subnet.aks_subnet.id
}

output "aks_nsg_id" {
  description = "ID of the Network Security Group for AKS"
  value       = azurerm_network_security_group.aks_nsg.id
}
