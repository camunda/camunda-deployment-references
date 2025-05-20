resource "azurerm_role_assignment" "dns_contributor" {
  scope                = var.dns_zone_id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = var.uami_object_id
}
