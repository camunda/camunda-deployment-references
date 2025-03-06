terraform {
  required_version = ">= 0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.0"
    }
  }
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "platform-aks"

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control_enabled = true

  default_node_pool {
    name            = "default"
    vm_size         = var.node_vm_size
    os_disk_size_gb = var.node_disk_size_gb
    vnet_subnet_id  = var.subnet_id
    node_count      = var.node_pool_count
  }

  tags = var.tags
}
