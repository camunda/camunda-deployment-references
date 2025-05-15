# PostgreSQL database
module "postgres_db" {
  source = "../../modules/postgres-db"

  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
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

  depends_on = [module.network]
}
