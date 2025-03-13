terraform {
  required_version = ">= 0.14"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = ">= 1.0"
    }
  }
}

# Create the PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "this" {
  name                         = var.server_name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = var.postgres_version
  delegated_subnet_id          = var.delegated_subnet_id
  private_dns_zone_id          = var.private_dns_zone_id
  administrator_login          = var.admin_username
  administrator_password       = var.admin_password
  sku_name                     = var.sku_tier
  storage_mb                   = var.storage_mb
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.enable_geo_redundant_backup

  zone = var.zone

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = var.standby_availability_zone
  }

  public_network_access_enabled = false
}

# Create the Keycloak database
resource "azurerm_postgresql_flexible_server_database" "keycloak" {
  name      = var.db_keycloak_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Create the Identity database
resource "azurerm_postgresql_flexible_server_database" "identity" {
  name      = var.db_identity_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Create the WebModeler database
resource "azurerm_postgresql_flexible_server_database" "webmodeler" {
  name      = var.db_webmodeler_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Configure the PostgreSQL provider to manage roles and grants
provider "postgresql" {
  host            = azurerm_postgresql_flexible_server.this.fqdn
  port            = 5432
  username        = var.admin_username
  password        = var.admin_password
  database        = "postgres"
  sslmode         = "require"
  connect_timeout = 15

  depends_on = [azurerm_postgresql_flexible_server.this]
}

# Create the Keycloak database connection role
resource "postgresql_role" "keycloak_role" {
  name     = var.db_keycloak_username
  password = var.db_keycloak_password
  login    = true
}

# Grant CONNECT privilege on Keycloak database
resource "postgresql_grant" "keycloak_grant" {
  database    = azurerm_postgresql_flexible_server_database.keycloak.name
  role        = postgresql_role.keycloak_role.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

# Create the Identity database connection role
resource "postgresql_role" "identity_role" {
  name     = var.db_identity_username
  password = var.db_identity_password
  login    = true
}

# Grant CONNECT privilege on Identity database
resource "postgresql_grant" "identity_grant" {
  database    = azurerm_postgresql_flexible_server_database.identity.name
  role        = postgresql_role.identity_role.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

# Create the WebModeler database connection role
resource "postgresql_role" "webmodeler_role" {
  name     = var.db_webmodeler_username
  password = var.db_webmodeler_password
  login    = true
}

# Grant CONNECT privilege on WebModeler database
resource "postgresql_grant" "webmodeler_grant" {
  database    = azurerm_postgresql_flexible_server_database.webmodeler.name
  role        = postgresql_role.webmodeler_role.name
  object_type = "database"
  privileges  = ["CONNECT"]
}
