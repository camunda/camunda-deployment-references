resource "azurerm_key_vault_key" "this" {
  depends_on      = [azurerm_key_vault_access_policy.tf_kv, azurerm_key_vault_access_policy.aks_kms]
  name            = var.key_name
  key_vault_id    = azurerm_key_vault.this.id
  key_type        = "RSA"
  key_size        = 3072
  key_opts        = ["encrypt", "decrypt"]
  expiration_date = timeadd(timestamp(), "8760h")
}
