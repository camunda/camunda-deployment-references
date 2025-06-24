module "kms" {
  source              = "../../modules/kms"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = local.location
  tags                = var.tags

  kv_name  = "${local.resource_prefix}-kv"
  key_name = "${local.resource_prefix}-kek"
  uai_name = "${local.resource_prefix}-uai"

  terraform_sp_app_id = var.terraform_sp_app_id
}
