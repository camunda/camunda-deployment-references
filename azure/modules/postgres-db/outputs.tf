output "fqdn" {
  description = "The fully qualified domain name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "server_id" {
  description = "The ID of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.this.id
}

output "admin_username" {
  description = "The administrator username for the PostgreSQL Flexible Server"
  value       = var.admin_username
  sensitive   = true
}
