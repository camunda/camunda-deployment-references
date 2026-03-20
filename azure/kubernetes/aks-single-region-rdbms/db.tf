# DB locals for RDBMS secondary storage variant
# This variant uses PostgreSQL as both the primary database (Identity)
# and as the secondary datastore (replacing Elasticsearch/OpenSearch).
locals {
  db_admin_username = "secret_user"    # Replace with your admin username
  db_admin_password = "secretvalue%23" # Replace with your admin password, password must contain at least one letter, one number, and one special character.

  camunda_database_identity = "camunda_identity" # Name of your camunda database for Identity

  # Connection configuration
  camunda_identity_db_username = "identity_db" # Username for connection to the Identity db
  camunda_identity_db_password = "secretvalue%25" # Replace with a password for the Identity db

  # RDBMS secondary storage database (replaces Elasticsearch/OpenSearch)
  camunda_database_secondary    = "camunda_secondary" # Name of the database used as RDBMS secondary storage
  camunda_secondary_db_username = "secondary_db"      # Username for connection to the RDBMS secondary storage DB
  camunda_secondary_db_password = "secretvalue%27"    # Replace with a password for the RDBMS secondary storage DB
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
