locals {
  resource_prefix     = ""              # Change this to a name of your choice
  cluster_name        = ""              # Change this to a name of your choice, if not provided, it will be set to resource_prefix-aks
  resource_group_name = ""              # Change this to a name of your choice, if not provided, it will be set to resource_prefix-rg
  location            = "swedencentral" # Change this to your desired Azure region
  # renovate: datasource=endoflife-date depName=azure-aks versioning=loose
  kubernetes_version = "1.32" # Change this to your desired Kubernetes version (aks - major.minor)

  db_admin_username = "secret_user"    # Replace with your Aurora username
  db_admin_password = "secretvalue%23" # Replace with your Aurora password, password must contain at least one letter, one number, and one special character.

  camunda_database_keycloak   = "camunda_keycloak"   # Name of your camunda database for Keycloak
  camunda_database_identity   = "camunda_identity"   # Name of your camunda database for Identity
  camunda_database_webmodeler = "camunda_webmodeler" # Name of your camunda database for WebModeler

  # Connection configuration
  camunda_keycloak_db_username   = "keycloak_db"   # This is the username that will be used for connection to the DB on Keycloak db
  camunda_identity_db_username   = "identity_db"   # This is the username that will be used for connection to the DB on Identity db
  camunda_webmodeler_db_username = "webmodeler_db" # This is the username that will be used for connection to the DB on WebModeler db

  camunda_keycloak_db_password   = "secretvalue%24" # Replace with a password that will be used for connection to the DB on Keycloak db
  camunda_identity_db_password   = "secretvalue%25" # Replace with a password that will be used for connection to the DB on Identity db
  camunda_webmodeler_db_password = "secretvalue%26" # Replace with a password that will be used for connection to the DB on WebModeler db
}

resource "azurerm_resource_group" "app_rg" {
  name     = local.resource_group_name != "" ? local.resource_group_name : "${local.resource_prefix}-rg"
  location = var.location
  tags     = var.tags
}

module "network" {
  source              = "../../modules/network"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  resource_prefix     = local.resource_prefix
  nsg_name            = "${local.resource_prefix}-aks-nsg"

  # Network address configuration
  vnet_address_space        = var.vnet_address_space
  aks_subnet_address_prefix = var.aks_subnet_address_prefix
  db_subnet_address_prefix  = var.db_subnet_address_prefix
  pe_subnet_address_prefix  = var.pe_subnet_address_prefix

  tags = var.tags
}

module "aks" {
  source              = "../../modules/aks"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  aks_cluster_name    = local.cluster_name != "" ? local.cluster_name : "${local.resource_prefix}-aks"
  subnet_id           = module.network.aks_subnet_id
  tags                = var.tags

  # Production-grade configuration with separate node pools
  kubernetes_version = var.kubernetes_version

  # Network configuration
  network_plugin = var.aks_network_plugin
  network_policy = var.aks_network_policy
  pod_cidr       = var.aks_pod_cidr
  service_cidr   = var.aks_service_cidr
  dns_service_ip = var.aks_dns_service_ip
  # docker_bridge_cidr parameter removed

  # System node pool configuration (for Kubernetes system components)
  system_node_pool_vm_size = var.system_node_pool_vm_size
  system_node_pool_count   = var.system_node_pool_count
  system_node_disk_size_gb = 30
  system_node_pool_zones   = var.system_node_pool_zones

  # User node pool configuration (for Camunda workloads)
  user_node_pool_vm_size = var.user_node_pool_vm_size
  user_node_pool_count   = var.user_node_pool_count
  user_node_disk_size_gb = 30
  user_node_pool_zones   = var.user_node_pool_zones

  enable_kms = true
  uami_id    = module.kms.uami_id
  kms_key_id = module.kms.key_vault_key_id

  depends_on = [
    module.network,
    module.kms,
    module.kms.azurerm_key_vault_access_policy.aks_kms
  ]
}

module "kms" {
  source              = "../../modules/kms"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  tags                = var.tags

  kv_name  = "${local.resource_prefix}-kv"
  key_name = "${local.resource_prefix}-kek"
  uai_name = "${local.resource_prefix}-uai"

  terraform_sp_app_id = var.terraform_sp_app_id
}


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
