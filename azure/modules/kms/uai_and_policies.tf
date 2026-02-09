# User Assigned Identity for AKS to access Key Vault
# Access is managed via RBAC role assignments (see role_assignments.tf)
# Reference: https://learn.microsoft.com/azure/key-vault/general/rbac-migration
resource "azurerm_user_assigned_identity" "this" {
  name                = var.uai_name
  resource_group_name = var.resource_group_name
  location            = var.location
}
