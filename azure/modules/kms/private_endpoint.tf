# Private endpoint for secure access to Key Vault
resource "azurerm_private_endpoint" "keyvault" {
  name                = "${var.kv_name}-endpoint"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.kv_name}-privateserviceconnection"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "keyvault-dns-group"
    private_dns_zone_ids = [var.keyvault_private_dns_zone_id]
  }
}
