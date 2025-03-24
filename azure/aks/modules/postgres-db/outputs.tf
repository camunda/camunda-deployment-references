output "fqdn" {
  description = "The fully qualified domain name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "server_id" {
  description = "The ID of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.this.id
}

output "connection_details" {
  description = "Connection details for the Camunda databases"
  value = {
    for db_key, db in var.databases : db_key => {
      host              = azurerm_postgresql_flexible_server.this.fqdn
      port              = 5432
      database          = db.name
      username          = db.username
      password          = lookup(var.database_passwords, db_key, "")
      connection_string = "postgresql://${db.username}:${lookup(var.database_passwords, db_key, "")}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/${db.name}"
    }
  }
  sensitive = true
}

output "databases" {
  description = "List of created database names"
  value       = [for db in azurerm_postgresql_flexible_server_database.databases : db.name]
}

output "admin_username" {
  description = "The administrator username for the PostgreSQL Flexible Server"
  value       = var.admin_username
  sensitive   = true
}
