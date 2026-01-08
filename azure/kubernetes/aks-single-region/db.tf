# DB locals
locals {
  db_admin_username = "secret_user"    # Replace with your Aurora username
  db_admin_password = "secretvalue%23" # Replace with your Aurora password, password must contain at least one letter, one number, and one special character.

  camunda_database_identity   = "camunda_identity"   # Name of your camunda database for Identity
  camunda_database_webmodeler = "camunda_webmodeler" # Name of your camunda database for WebModeler

  # Connection configuration
  camunda_identity_db_username   = "identity_db"   # This is the username that will be used for connection to the DB on Identity db
  camunda_webmodeler_db_username = "webmodeler_db" # This is the username that will be used for connection to the DB on WebModeler db

  camunda_identity_db_password   = "secretvalue%25" # Replace with a password that will be used for connection to the DB on Identity db
  camunda_webmodeler_db_password = "secretvalue%26" # Replace with a password that will be used for connection to the DB on WebModeler db
}

# PostgreSQL database
module "postgres_db" {
  source = "../../modules/postgres-db"

  resource_group_name = azurerm_resource_group.app_rg.name
  location            = local.location
  tags                = var.tags

  server_name      = "${local.resource_prefix}-pg-server"
  admin_username   = local.db_admin_username
  admin_password   = local.db_admin_password
  postgres_version = var.postgres_version
  sku_tier         = var.postgres_sku_tier
  storage_mb       = var.postgres_storage_mb

  backup_retention_days       = var.postgres_backup_retention_days
  enable_geo_redundant_backup = var.postgres_enable_geo_redundant_backup
  zone                        = var.postgres_zone
  standby_availability_zone   = var.postgres_standby_zone

  private_endpoint_subnet_id = module.network.pe_subnet_id
  private_dns_zone_id        = module.network.postgres_private_dns_zone_id
}

# DB outputs
output "postgres_fqdn" {
  description = "The fully qualified domain name of the PostgreSQL Flexible Server"
  value       = module.postgres_db.fqdn
}

output "postgres_admin_username" {
  description = "PostgreSQL admin user"
  value       = local.db_admin_username
}

output "postgres_admin_password" {
  description = "PostgreSQL admin password"
  value       = local.db_admin_password
  sensitive   = true
}
