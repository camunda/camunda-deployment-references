module "network" {
  source              = "../../modules/network"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = local.location
  resource_prefix     = local.resource_prefix
  nsg_name            = "${local.resource_prefix}-aks-nsg"

  # Network address configuration
  vnet_address_space        = var.vnet_address_space
  aks_subnet_address_prefix = var.aks_subnet_address_prefix
  db_subnet_address_prefix  = var.db_subnet_address_prefix
  pe_subnet_address_prefix  = var.pe_subnet_address_prefix

  tags = var.tags
}
