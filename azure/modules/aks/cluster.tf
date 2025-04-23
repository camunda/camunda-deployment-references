# Production-ready AKS cluster for Camunda Platform
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
  # For differences between system and user node pools, see: https://learn.microsoft.com/en-us/azure/aks/node-pool-overview
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

  # Network configuration with configurable CIDRs
  network_profile {
    network_plugin    = var.network_plugin
    network_policy    = var.network_policy
    load_balancer_sku = "standard"

    # Configurable network CIDRs
    pod_cidr       = var.network_plugin == "kubenet" ? var.pod_cidr : null
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
  }

  private_cluster_enabled = false
}
