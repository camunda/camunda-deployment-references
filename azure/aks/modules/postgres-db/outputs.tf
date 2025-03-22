output "fqdn" {
  description = "The fully qualified domain name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "connection_details" {
  description = "Connection details for the Camunda databases"
  value = {
    keycloak = {
      host     = azurerm_postgresql_flexible_server.this.fqdn
      port     = 5432
      database = azurerm_postgresql_flexible_server_database.keycloak.name
      username = var.db_keycloak_username
      password = var.db_keycloak_password
    }
    identity = {
      host     = azurerm_postgresql_flexible_server.this.fqdn
      port     = 5432
      database = azurerm_postgresql_flexible_server_database.identity.name
      username = var.db_identity_username
      password = var.db_identity_password
    }
    webmodeler = {
      host     = azurerm_postgresql_flexible_server.this.fqdn
      port     = 5432
      database = azurerm_postgresql_flexible_server_database.webmodeler.name
      username = var.db_webmodeler_username
      password = var.db_webmodeler_password
    }
  }
  sensitive = true
}
