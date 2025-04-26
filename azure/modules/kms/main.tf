data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                            = var.kv_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  tags                            = var.tags

  network_acls {
    default_action = "Deny"          # block everything unless explicitly allowed
    bypass         = "AzureServices" # let Azure infra (AKS control-plane) through
  }

  soft_delete_retention_days = 90   # keep deleted objects for 90 days
  purge_protection_enabled   = true # prevent purge while soft_delete is active
}

resource "azurerm_key_vault_key" "this" {
  name         = var.key_name
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA"
  key_size     = 3072
  key_opts     = ["encrypt", "decrypt"]

  expiration_date = timeadd(timestamp(), "8760h") # 1 year
}

resource "azurerm_user_assigned_identity" "this" {
  name                = var.uai_name
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_key_vault_access_policy" "aks_kms" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.aks_uai.principal_id

  key_permissions = [
    "Encrypt",
    "Decrypt",
    "WrapKey",
    "UnwrapKey",
  ]
}

data "azuread_service_principal" "terraform_sp" {
  client_id = var.terraform_sp_app_id
}

resource "azurerm_key_vault_access_policy" "tf_kv" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azuread_service_principal.terraform_sp.object_id

  key_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "WrapKey",
    "UnwrapKey",
  ]
  secret_permissions = []
}
