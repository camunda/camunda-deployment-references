data "azurerm_client_config" "current" {}

# Lookup the Terraform SP so we can grant it permissions
data "azuread_service_principal" "terraform_sp" {
  client_id = var.terraform_sp_app_id
}

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
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  soft_delete_retention_days = 90
  purge_protection_enabled   = true
}

resource "azurerm_user_assigned_identity" "this" {
  name                = var.uai_name
  resource_group_name = var.resource_group_name
  location            = var.location
}

# AKS UAMI needs wrap/unwrap at runtime
resource "azurerm_key_vault_access_policy" "aks_kms" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.this.principal_id

  key_permissions = [
    "Encrypt",
    "Decrypt",
    "WrapKey",
    "UnwrapKey",
  ]
}

# Terraform SP needs full key-management rights before key creation
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

resource "azurerm_key_vault_key" "this" {
  depends_on      = [azurerm_key_vault_access_policy.tf_kv]
  name            = var.key_name
  key_vault_id    = azurerm_key_vault.this.id
  key_type        = "RSA"
  key_size        = 3072
  key_opts        = ["encrypt", "decrypt"]
  expiration_date = timeadd(timestamp(), "8760h")
}
