# aks

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [azurerm_kubernetes_cluster.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_role_assignment.kubelet_dns](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aks_cluster_name"></a> [aks\_cluster\_name](#input\_aks\_cluster\_name) | Name of the AKS cluster | `string` | n/a | yes |
| <a name="input_dns_service_ip"></a> [dns\_service\_ip](#input\_dns\_service\_ip) | IP address within the service CIDR that will be used for DNS | `string` | `"10.0.0.10"` | no |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | The Azure DNS zone resource id for ExternalDNS or cert-manager | `string` | `null` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | Key Vault Key ID for envelope-encryption | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version to use for the AKS cluster | `string` | `"1.34"` | no |
| <a name="input_location"></a> [location](#input\_location) | Region where the AKS cluster will be deployed | `string` | n/a | yes |
| <a name="input_network_plugin"></a> [network\_plugin](#input\_network\_plugin) | Network plugin to use for Kubernetes networking | `string` | `"azure"` | no |
| <a name="input_network_policy"></a> [network\_policy](#input\_network\_policy) | Network policy to use for Kubernetes networking | `string` | `"calico"` | no |
| <a name="input_pe_subnet_address_prefix"></a> [pe\_subnet\_address\_prefix](#input\_pe\_subnet\_address\_prefix) | Address prefix for the private endpoint subnet | `list(string)` | <pre>[<br/>  "10.1.2.0/24"<br/>]</pre> | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | CIDR block for pod IP addresses | `string` | `"10.244.0.0/16"` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the Azure resource group | `string` | n/a | yes |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | CIDR block for Kubernetes service IP addresses | `string` | `"10.0.0.0/16"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the subnet where the AKS cluster will be deployed | `string` | n/a | yes |
| <a name="input_system_node_disk_size_gb"></a> [system\_node\_disk\_size\_gb](#input\_system\_node\_disk\_size\_gb) | OS disk size in GB for system nodes | `number` | `30` | no |
| <a name="input_system_node_pool_count"></a> [system\_node\_pool\_count](#input\_system\_node\_pool\_count) | Number of nodes in the system node pool | `number` | `3` | no |
| <a name="input_system_node_pool_vm_size"></a> [system\_node\_pool\_vm\_size](#input\_system\_node\_pool\_vm\_size) | VM size for the system node pool | `string` | `"Standard_D2s_v3"` | no |
| <a name="input_system_node_pool_zones"></a> [system\_node\_pool\_zones](#input\_system\_node\_pool\_zones) | AZs for system node pool, e.g. ["1","2","3"] | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_uami_id"></a> [uami\_id](#input\_uami\_id) | User-assigned identity ID to use for KMS | `string` | n/a | yes |
| <a name="input_uami_object_id"></a> [uami\_object\_id](#input\_uami\_object\_id) | User-assigned identity object ID to use for KMS | `string` | n/a | yes |
| <a name="input_user_node_disk_size_gb"></a> [user\_node\_disk\_size\_gb](#input\_user\_node\_disk\_size\_gb) | OS disk size in GB for user nodes | `number` | `30` | no |
| <a name="input_user_node_pool_count"></a> [user\_node\_pool\_count](#input\_user\_node\_pool\_count) | Number of nodes in the user node pool | `number` | `2` | no |
| <a name="input_user_node_pool_drain_timeout_in_minutes"></a> [user\_node\_pool\_drain\_timeout\_in\_minutes](#input\_user\_node\_pool\_drain\_timeout\_in\_minutes) | The amount of time in minutes to wait on eviction of pods and graceful termination per node | `number` | `0` | no |
| <a name="input_user_node_pool_max_surge"></a> [user\_node\_pool\_max\_surge](#input\_user\_node\_pool\_max\_surge) | The maximum number or percentage of nodes which will be added to the Node Pool size during an upgrade | `number` | `10` | no |
| <a name="input_user_node_pool_node_soak_duration_in_minutes"></a> [user\_node\_pool\_node\_soak\_duration\_in\_minutes](#input\_user\_node\_pool\_node\_soak\_duration\_in\_minutes) | The amount of time in minutes to wait after draining a node and before reimaging and moving on to next node | `number` | `0` | no |
| <a name="input_user_node_pool_vm_size"></a> [user\_node\_pool\_vm\_size](#input\_user\_node\_pool\_vm\_size) | VM size for the user node pool | `string` | `"Standard_D4s_v3"` | no |
| <a name="input_user_node_pool_zones"></a> [user\_node\_pool\_zones](#input\_user\_node\_pool\_zones) | AZs for user node pool | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aks_cluster_id"></a> [aks\_cluster\_id](#output\_aks\_cluster\_id) | ID of the deployed AKS cluster |
| <a name="output_aks_cluster_name"></a> [aks\_cluster\_name](#output\_aks\_cluster\_name) | Name of the AKS cluster |
| <a name="output_aks_fqdn"></a> [aks\_fqdn](#output\_aks\_fqdn) | FQDN of the AKS cluster |
| <a name="output_aks_kube_config"></a> [aks\_kube\_config](#output\_aks\_kube\_config) | Kube config to connect to the AKS cluster |
<!-- END_TF_DOCS -->
