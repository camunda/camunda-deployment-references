# aks

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_aks"></a> [aks](#module\_aks) | ../../modules/aks | n/a |
| <a name="module_kms"></a> [kms](#module\_kms) | ../../modules/kms | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../../modules/network | n/a |
| <a name="module_postgres_db"></a> [postgres\_db](#module\_postgres\_db) | ../../modules/postgres-db | n/a |
## Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.app_rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aks_dns_service_ip"></a> [aks\_dns\_service\_ip](#input\_aks\_dns\_service\_ip) | IP address within the service CIDR that will be used for DNS | `string` | `"10.0.0.10"` | no |
| <a name="input_aks_network_plugin"></a> [aks\_network\_plugin](#input\_aks\_network\_plugin) | Network plugin to use for Kubernetes networking | `string` | `"azure"` | no |
| <a name="input_aks_network_policy"></a> [aks\_network\_policy](#input\_aks\_network\_policy) | Network policy to use for Kubernetes networking | `string` | `"calico"` | no |
| <a name="input_aks_pod_cidr"></a> [aks\_pod\_cidr](#input\_aks\_pod\_cidr) | CIDR block for pod IP addresses (only used with kubenet) | `string` | `"10.244.0.0/16"` | no |
| <a name="input_aks_service_cidr"></a> [aks\_service\_cidr](#input\_aks\_service\_cidr) | CIDR block for Kubernetes service IP addresses | `string` | `"10.0.0.0/16"` | no |
| <a name="input_aks_subnet_address_prefix"></a> [aks\_subnet\_address\_prefix](#input\_aks\_subnet\_address\_prefix) | Address prefix for the AKS subnet | `list(string)` | <pre>[<br/>  "10.1.0.0/24"<br/>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Optional override for the AKS cluster name | `string` | `""` | no |
| <a name="input_db_subnet_address_prefix"></a> [db\_subnet\_address\_prefix](#input\_db\_subnet\_address\_prefix) | Address prefix for the database subnet | `list(string)` | <pre>[<br/>  "10.1.1.0/24"<br/>]</pre> | no |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | Azure Resource ID of the shared DNS zone | `string` | `null` | no |
| <a name="input_pe_subnet_address_prefix"></a> [pe\_subnet\_address\_prefix](#input\_pe\_subnet\_address\_prefix) | Address prefix for the private endpoint subnet | `list(string)` | <pre>[<br/>  "10.1.2.0/24"<br/>]</pre> | no |
| <a name="input_postgres_backup_retention_days"></a> [postgres\_backup\_retention\_days](#input\_postgres\_backup\_retention\_days) | Backup retention days for PostgreSQL | `number` | `7` | no |
| <a name="input_postgres_enable_geo_redundant_backup"></a> [postgres\_enable\_geo\_redundant\_backup](#input\_postgres\_enable\_geo\_redundant\_backup) | Enable geo-redundant backup for PostgreSQL | `bool` | `true` | no |
| <a name="input_postgres_sku_tier"></a> [postgres\_sku\_tier](#input\_postgres\_sku\_tier) | SKU tier for PostgreSQL Flexible Server | `string` | `"GP_Standard_D2s_v3"` | no |
| <a name="input_postgres_standby_zone"></a> [postgres\_standby\_zone](#input\_postgres\_standby\_zone) | Standby Availability Zone for PostgreSQL high availability | `string` | `"2"` | no |
| <a name="input_postgres_storage_mb"></a> [postgres\_storage\_mb](#input\_postgres\_storage\_mb) | Storage size in MB for PostgreSQL | `number` | `32768` | no |
| <a name="input_postgres_version"></a> [postgres\_version](#input\_postgres\_version) | PostgreSQL version | `string` | `"15"` | no |
| <a name="input_postgres_zone"></a> [postgres\_zone](#input\_postgres\_zone) | Primary Availability Zone for PostgreSQL server | `string` | `"1"` | no |
| <a name="input_resource_prefix_placeholder"></a> [resource\_prefix\_placeholder](#input\_resource\_prefix\_placeholder) | Placeholder for the resource prefix | `string` | `""` | no |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | The Azure Subscription ID to deploy into | `string` | n/a | yes |
| <a name="input_system_node_pool_count"></a> [system\_node\_pool\_count](#input\_system\_node\_pool\_count) | Number of nodes in the system node pool | `number` | `1` | no |
| <a name="input_system_node_pool_vm_size"></a> [system\_node\_pool\_vm\_size](#input\_system\_node\_pool\_vm\_size) | VM size for the system node pool | `string` | `"Standard_D2s_v3"` | no |
| <a name="input_system_node_pool_zones"></a> [system\_node\_pool\_zones](#input\_system\_node\_pool\_zones) | List of AZs for the system node pool | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | <pre>{<br/>  "Environment": "Testing",<br/>  "Purpose": "Reference Implementation"<br/>}</pre> | no |
| <a name="input_terraform_sp_app_id"></a> [terraform\_sp\_app\_id](#input\_terraform\_sp\_app\_id) | The Service Principals Application (client) ID that Terraform is using | `string` | n/a | yes |
| <a name="input_user_node_pool_count"></a> [user\_node\_pool\_count](#input\_user\_node\_pool\_count) | Number of nodes in the user node pool | `number` | `5` | no |
| <a name="input_user_node_pool_vm_size"></a> [user\_node\_pool\_vm\_size](#input\_user\_node\_pool\_vm\_size) | VM size for the user node pool | `string` | `"Standard_D4s_v3"` | no |
| <a name="input_user_node_pool_zones"></a> [user\_node\_pool\_zones](#input\_user\_node\_pool\_zones) | List of AZs for the user node pool | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Address space for the virtual network | `list(string)` | <pre>[<br/>  "10.1.0.0/16"<br/>]</pre> | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aks_cluster_id"></a> [aks\_cluster\_id](#output\_aks\_cluster\_id) | ID of the deployed AKS cluster |
| <a name="output_aks_cluster_name"></a> [aks\_cluster\_name](#output\_aks\_cluster\_name) | Name of the AKS cluster |
| <a name="output_aks_fqdn"></a> [aks\_fqdn](#output\_aks\_fqdn) | FQDN of the AKS cluster |
| <a name="output_camunda_database_identity"></a> [camunda\_database\_identity](#output\_camunda\_database\_identity) | n/a |
| <a name="output_camunda_database_webmodeler"></a> [camunda\_database\_webmodeler](#output\_camunda\_database\_webmodeler) | n/a |
| <a name="output_camunda_identity_db_password"></a> [camunda\_identity\_db\_password](#output\_camunda\_identity\_db\_password) | n/a |
| <a name="output_camunda_identity_db_username"></a> [camunda\_identity\_db\_username](#output\_camunda\_identity\_db\_username) | n/a |
| <a name="output_camunda_webmodeler_db_password"></a> [camunda\_webmodeler\_db\_password](#output\_camunda\_webmodeler\_db\_password) | n/a |
| <a name="output_camunda_webmodeler_db_username"></a> [camunda\_webmodeler\_db\_username](#output\_camunda\_webmodeler\_db\_username) | n/a |
| <a name="output_postgres_admin_password"></a> [postgres\_admin\_password](#output\_postgres\_admin\_password) | PostgreSQL admin password |
| <a name="output_postgres_admin_username"></a> [postgres\_admin\_username](#output\_postgres\_admin\_username) | PostgreSQL admin user |
| <a name="output_postgres_fqdn"></a> [postgres\_fqdn](#output\_postgres\_fqdn) | The fully qualified domain name of the PostgreSQL Flexible Server |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group |
<!-- END_TF_DOCS -->
