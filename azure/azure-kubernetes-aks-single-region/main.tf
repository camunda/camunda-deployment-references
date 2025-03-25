resource "azurerm_resource_group" "app_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "network" {
  source              = "../modules/network"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  resource_prefix     = var.resource_prefix
  nsg_name            = "${var.resource_prefix}-aks-nsg"
  tags                = var.tags
}

module "aks" {
  source              = "../modules/aks"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  aks_cluster_name    = "${var.resource_prefix}-aks"
  subnet_id           = module.network.aks_subnet_id
  # System node pool configuration (for Kubernetes system components)
  system_node_pool_vm_size = "Standard_D2s_v3"
  system_node_pool_count   = 1
  system_node_disk_size_gb = 30

  # User node pool configuration (for Camunda workloads)
  user_node_pool_vm_size = "Standard_D4s_v3"
  user_node_pool_count   = 2
  user_node_disk_size_gb = 50
  tags                   = var.tags
  depends_on             = [module.network]
  kubernetes_version     = var.kubernetes_version
}

module "postgres_db" {
  source = "../modules/postgres-db"

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

  databases          = var.databases
  database_passwords = var.database_passwords

  depends_on = [module.network]
}

# Local resource to indicate test readiness
resource "local_file" "deployment_complete" {
  content  = "Deployment completed on ${timestamp()}"
  filename = "${path.module}/deployment_complete.txt"

  depends_on = [
    module.aks,
    module.postgres_db
  ]
}
