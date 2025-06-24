resource "azurerm_role_assignment" "kubelet_dns" {
  count                = var.dns_zone_id != null ? 1 : 0
  scope                = var.dns_zone_id
  role_definition_name = "DNS Zone Contributor"

  principal_id   = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  principal_type = "ServicePrincipal"
}
