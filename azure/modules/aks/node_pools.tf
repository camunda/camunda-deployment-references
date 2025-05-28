# User node pool for Camunda workloads
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.user_node_pool_vm_size
  os_disk_size_gb       = var.user_node_disk_size_gb
  vnet_subnet_id        = var.subnet_id
  orchestrator_version  = var.kubernetes_version
  zones                 = var.user_node_pool_zones

  node_count = var.user_node_pool_count

  # Node labels
  node_labels = {
    "nodepool-type" = "user"
    "app"           = "camunda"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.uami_id]
  }

  # Keep things simple
  max_pods = 30
  tags     = var.tags
}
