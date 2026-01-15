locals {
  # renovate: datasource=endoflife-date depName=azure-kubernetes-service versioning=loose
  kubernetes_version = "1.34" # Change this to your desired Kubernetes version (aks - major.minor)
}

module "aks" {
  source              = "../../modules/aks"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = local.location
  aks_cluster_name    = "${local.resource_prefix}-aks"
  subnet_id           = module.network.aks_subnet_id
  tags                = var.tags

  # Production-grade configuration with separate node pools
  kubernetes_version = local.kubernetes_version

  # Network configuration
  network_plugin = var.aks_network_plugin
  network_policy = var.aks_network_policy
  pod_cidr       = var.aks_pod_cidr
  service_cidr   = var.aks_service_cidr
  dns_service_ip = var.aks_dns_service_ip

  # System node pool configuration (for Kubernetes system components)
  system_node_pool_vm_size = var.system_node_pool_vm_size
  system_node_pool_count   = var.system_node_pool_count
  system_node_disk_size_gb = 30
  system_node_pool_zones   = var.system_node_pool_zones

  # User node pool configuration (for Camunda workloads)
  user_node_pool_vm_size = var.user_node_pool_vm_size
  user_node_pool_count   = var.user_node_pool_count
  user_node_disk_size_gb = 30
  user_node_pool_zones   = var.user_node_pool_zones

  uami_id        = module.kms.uami_id
  uami_object_id = module.kms.uami_object_id
  kms_key_id     = module.kms.key_vault_key_id

  dns_zone_id = var.dns_zone_id
}
