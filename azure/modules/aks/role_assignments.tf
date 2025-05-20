variable "dns_zone_name" {
  description = "Name of the Azure DNS zone (global resource)"
  type        = string
  default     = "azure.camunda.ie"
}

variable "dns_zone_resource_group" {
  description = "Resource group of the Azure DNS zone"
  type        = string
  default     = "rg-infraex-global-permanent"
}

data "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group
}

resource "azurerm_role_assignment" "dns_contributor" {
  scope                = data.azurerm_dns_zone.main.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = module.kms.uami_object_id
}
