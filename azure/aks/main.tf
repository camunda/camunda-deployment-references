resource "azurerm_resource_group" "app_rg" {
  name     = var.resource_group_name
  location = var.location
}

module "network" {
  source              = "./modules/network"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  nsg_name            = "camunda-aks-nsg"
}

module "aks" {
  source              = "./modules/aks"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  aks_cluster_name    = var.aks_cluster_name
  subnet_id           = module.network.aks_subnet_id
  node_pool_count     = var.node_pool_count
  tags                = var.tags
  depends_on          = [module.network]
}

module "postgres_db" {
  source              = "./modules/postgres-db"

  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location

  server_name         = var.postgres_server_name
  admin_username      = var.db_admin_username
  admin_password      = var.db_admin_password
  postgres_version    = "15"
  sku_tier            = var.postgres_sku_tier
  storage_mb          = var.postgres_storage_mb
  backup_retention_days = var.postgres_backup_retention_days
  enable_geo_redundant_backup = var.postgres_enable_geo_redundant_backup

  delegated_subnet_id = module.network.db_subnet_id
  private_dns_zone_id = module.network.postgres_private_dns_zone_id

  zone                = var.postgres_zone
  standby_availability_zone = var.postgres_standby_zone

  db_keycloak_name       = var.db_keycloak_name
  db_identity_name       = var.db_identity_name
  db_webmodeler_name     = var.db_webmodeler_name

  db_keycloak_username   = var.db_keycloak_username
  db_identity_username   = var.db_identity_username
  db_webmodeler_username = var.db_webmodeler_username

  db_keycloak_password   = var.db_keycloak_password
  db_identity_password   = var.db_identity_password
  db_webmodeler_password = var.db_webmodeler_password
}

output "postgres_fqdn" {
  value = module.postgres_db.fqdn
}
