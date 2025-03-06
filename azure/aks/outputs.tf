output "aks_cluster_id" {
  value = module.aks.aks_cluster_id
}

output "network_security_group_id" {
  value = module.network.aks_nsg_id
}
