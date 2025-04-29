data "azurerm_client_config" "current" {}

data "azuread_service_principal" "terraform_sp" {
  client_id = var.terraform_sp_app_id
}
