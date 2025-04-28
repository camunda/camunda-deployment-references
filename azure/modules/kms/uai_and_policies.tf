resource "azurerm_user_assigned_identity" "this" {
  name                = var.uai_name
  resource_group_name = var.resource_group_name
  location            = var.location
}

# AKS needs wrap/unwrap
resource "azurerm_key_vault_access_policy" "aks_kms" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.this.principal_id

  key_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Update",
    "Import",
    "Encrypt",
    "Decrypt",
    "WrapKey",
    "UnwrapKey",
  ]
}

# Terraform SP needs full key rights
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
    "GetRotationPolicy",
    "SetRotationPolicy",
    "Update",
    "Rotate",
  ]
}
