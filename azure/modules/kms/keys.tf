resource "azurerm_key_vault_key" "this" {
  name            = var.key_name
  key_vault_id    = azurerm_key_vault.this.id
  key_type        = "RSA"
  key_size        = 3072
  key_opts        = ["encrypt", "decrypt"]
  expiration_date = var.key_expiration_date

  depends_on = [
    azurerm_role_assignment.tf_sp_kv_admin,
    azurerm_role_assignment.tf_sp_kv_crypto_officer
  ]
}
