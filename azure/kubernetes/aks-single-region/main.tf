resource "azurerm_resource_group" "app_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "network" {
  source              = "../../modules/network"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  resource_prefix     = var.resource_prefix
  nsg_name            = "${var.resource_prefix}-aks-nsg"

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
  aks_cluster_name    = "${var.resource_prefix}-aks"
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

  # User node pool configuration (for Camunda workloads)
  user_node_pool_vm_size = var.user_node_pool_vm_size
  user_node_pool_count   = var.user_node_pool_count
  user_node_disk_size_gb = 30

  depends_on = [module.network]
}

# PostgreSQL database
module "postgres_db" {
  source = "../../modules/postgres-db"

  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  tags                = var.tags

  server_name      = "${var.resource_prefix}-pg-server"
  admin_username   = var.db_admin_username
  admin_password   = var.db_admin_password
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
