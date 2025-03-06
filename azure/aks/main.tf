resource "azurerm_resource_group" "app_rg" {
  name     = var.resource_group_name
  location = var.location
}

module "network" {
  source              = "./modules/network"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = var.location
  nsg_name            = "camunda-aks-nsg"
  enable_nsg          = true
}

module "aks" {
  source                = "./modules/aks"
  resource_group_name   = azurerm_resource_group.app_rg.name
  location              = var.location
  aks_cluster_name      = var.aks_cluster_name
  subnet_id             = module.network.aks_subnet_id
  admin_group_object_id = var.admin_group_object_id
  node_pool_count       = var.node_pool_count
  api_private_access    = var.api_private_access
  private_dns_zone_id   = var.private_dns_zone_id
  api_allowed_ip_ranges = var.api_allowed_ip_ranges
  tags                  = var.tags
  depends_on            = [module.network]
}
