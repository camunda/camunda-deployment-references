resource "azurerm_postgresql_flexible_server" "this" {
  name                         = var.server_name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = var.postgres_version
  administrator_login          = var.admin_username
  administrator_password       = var.admin_password
  sku_name                     = var.sku_tier
  storage_mb                   = var.storage_mb
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.enable_geo_redundant_backup
  tags                         = var.tags

  zone = var.zone

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = var.standby_availability_zone
  }

  public_network_access_enabled = false

  lifecycle {
    ignore_changes = [
      # Ignore changes to this specific tag during terraform operations
      tags["testing"],
    ]
  }
}
