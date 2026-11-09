output "key_vault_id" {
  description = "The Key Vault resource ID"
  value       = azurerm_key_vault.this.id

  # AKS consumes this ID for KMS; the vault read grant must exist before cluster creation.
  depends_on = [azurerm_role_assignment.uami_kv_reader]
}

output "key_vault_key_id" {
  description = "The versionless Key Vault key ID for envelope encryption"
  value       = azurerm_key_vault_key.this.versionless_id
}

output "uami_id" {
  description = "User-Assigned Managed Identity ID"
  value       = azurerm_user_assigned_identity.this.id
}

output "uami_object_id" {
  description = "Object ID (GUID) of the User Assigned Managed Identity"
  value       = azurerm_user_assigned_identity.this.principal_id
}
