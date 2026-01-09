resource "azurerm_key_vault" "this" {
  name                            = var.kv_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  tags                            = var.tags

  rbac_authorization_enabled = true

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  soft_delete_retention_days = 90
  purge_protection_enabled   = true
}
