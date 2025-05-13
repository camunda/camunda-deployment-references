# Grant the Key Vault access policy to AKS

resource "azurerm_role_assignment" "uami_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "uami_crypto_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

# Grant the SP applying terraform access to the Key Vault

resource "azurerm_role_assignment" "tf_sp_secrets_reader" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = data.azuread_service_principal.terraform_sp.object_id
}
