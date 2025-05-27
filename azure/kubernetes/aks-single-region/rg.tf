resource "azurerm_resource_group" "app_rg" {
  name     = local.resource_group_name != "" ? local.resource_group_name : "${local.resource_prefix}-rg"
  location = local.location
  tags     = var.tags
}
