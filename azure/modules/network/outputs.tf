output "aks_subnet_id" {
  description = "ID of the subnet where AKS is deployed"
  value       = azurerm_subnet.aks_subnet.id
}

output "aks_nsg_id" {
  description = "ID of the Network Security Group for AKS"
  value       = azurerm_network_security_group.aks_nsg.id
}

output "db_subnet_id" {
  description = "Subnet ID for PostgreSQL Flexible Server"
  value       = azurerm_subnet.db_subnet.id
}

output "postgres_private_dns_zone_id" {
  description = "Private DNS Zone ID for PostgreSQL Flexible Server"
  value       = azurerm_private_dns_zone.postgres.id
}

output "postgres_private_dns_zone_name" {
  description = "Private DNS Zone name for PostgreSQL Flexible Server"
  value       = azurerm_private_dns_zone.postgres.name
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.aks_vnet.id
}

output "pe_subnet_id" {
  description = "ID of the subnet for private endpoints"
  value       = azurerm_subnet.pe_subnet.id
}
