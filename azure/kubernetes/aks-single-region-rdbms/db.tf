# DB locals
locals {
  db_admin_username = "c8admin" # Azure Database for PostgreSQL Flexible Server admin username
  db_admin_password = random_password.db_admin.result

  camunda_database_identity   = "camunda_identity"   # Name of your camunda database for Identity
  camunda_database_webmodeler = "camunda_webmodeler" # Name of your camunda database for WebModeler

  # RDBMS secondary storage: additional database for orchestration (Operate, Tasklist)
  camunda_database_orchestration = "camunda_orchestration" # Name of your camunda database for orchestration secondary storage

  # Connection configuration
  camunda_identity_db_username   = "identity_db"   # Username for connection to the Identity DB
  camunda_webmodeler_db_username = "webmodeler_db" # Username for connection to the WebModeler DB

  # RDBMS secondary storage: dedicated user for orchestration DB
  camunda_orchestration_db_username = "orchestration_db" # Username for connection to the orchestration DB

  camunda_identity_db_password      = random_password.identity_db.result
  camunda_webmodeler_db_password    = random_password.webmodeler_db.result
  camunda_orchestration_db_password = random_password.orchestration_db.result
}

# Generate random passwords for database credentials
# To retrieve passwords after apply: terraform output -json | jq '.postgres_admin_password.value, .camunda_identity_db_password.value, .camunda_webmodeler_db_password.value, .camunda_orchestration_db_password.value'
resource "random_password" "db_admin" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "random_password" "identity_db" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "random_password" "webmodeler_db" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "random_password" "orchestration_db" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
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
