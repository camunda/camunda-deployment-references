resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.aks_cluster_name}-dns"
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  # Identity management
  identity {
    type = "SystemAssigned"
  }

  # System node pool configuration
  default_node_pool {
    name                 = "system"
    vm_size              = var.system_node_pool_vm_size
    os_disk_size_gb      = var.system_node_disk_size_gb
    vnet_subnet_id       = var.subnet_id
    node_count           = var.system_node_pool_count
    orchestrator_version = var.kubernetes_version

    # Node labels
    node_labels = {
      "nodepool-type" = "system"
      "environment"   = "production"
    }

    # Keep things simple for testing
    max_pods                     = 30
    only_critical_addons_enabled = true
  }

  # Network configuration
  network_profile {
    network_plugin    = "kubenet"
    network_policy    = "calico"
    load_balancer_sku = "standard"
  }

  private_cluster_enabled = false
}

# User node pool for Camunda workloads
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.user_node_pool_vm_size
  os_disk_size_gb       = var.user_node_disk_size_gb
  vnet_subnet_id        = var.subnet_id
  orchestrator_version  = var.kubernetes_version

  node_count = var.user_node_pool_count

  node_labels = {
    "nodepool-type" = "user"
    "app"           = "camunda"
  }

  max_pods = 30
  tags     = var.tags
}
