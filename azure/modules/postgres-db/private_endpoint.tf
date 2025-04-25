# Private endpoint for secure access to PostgreSQL
resource "azurerm_private_endpoint" "postgres" {
  name                = "${var.server_name}-endpoint"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.server_name}-privateserviceconnection"
    private_connection_resource_id = azurerm_postgresql_flexible_server.this.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "postgresql-dns-group"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
