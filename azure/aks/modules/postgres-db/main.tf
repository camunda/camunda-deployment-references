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

  # For testing purposes, we're enabling public access
  # In production, you would restrict this and use private endpoints
  public_network_access_enabled = true

  # For testing simplicity, allow all IP addresses to connect
  # NOT RECOMMENDED FOR PRODUCTION
  lifecycle {
    ignore_changes = [
      # This allows automated tests to run without worrying about IP changes
      tags["testing"],
    ]
  }
}

# For testing purposes, allow all IPs to connect to the PostgreSQL server
# NOT RECOMMENDED FOR PRODUCTION
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_all" {
  name             = "AllowAll"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

resource "azurerm_postgresql_flexible_server_database" "databases" {
  for_each = var.databases

  name      = each.value.name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  depends_on = [
    azurerm_postgresql_flexible_server_firewall_rule.allow_all
  ]
}

resource "local_file" "connection_info" {
  content = templatefile("${path.module}/templates/connection.tpl", {
    server_name = azurerm_postgresql_flexible_server.this.fqdn
    admin_user  = var.admin_username
    admin_pass  = var.admin_password
    databases = {
      for k, v in var.databases : k => {
        name     = v.name
        username = v.username
        password = lookup(var.database_passwords, k, "")
      }
    }
  })
  filename = "${path.module}/connection_info.txt"
}
