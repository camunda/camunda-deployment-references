# network

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [azurerm_network_security_group.aks_nsg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_group.pe_nsg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_private_dns_zone.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.postgres_vnet_link](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_subnet.aks_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.db_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.pe_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.aks_nsg_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.pe_nsg_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.aks_vnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aks_subnet_address_prefix"></a> [aks\_subnet\_address\_prefix](#input\_aks\_subnet\_address\_prefix) | Address prefix for the AKS subnet | `list(string)` | <pre>[<br/>  "10.1.0.0/24"<br/>]</pre> | no |
| <a name="input_api_server_authorized_ranges"></a> [api\_server\_authorized\_ranges](#input\_api\_server\_authorized\_ranges) | CIDR ranges authorized to access the Kubernetes API server | `string` | `"*"` | no |
| <a name="input_db_subnet_address_prefix"></a> [db\_subnet\_address\_prefix](#input\_db\_subnet\_address\_prefix) | Address prefix for the database subnet | `list(string)` | <pre>[<br/>  "10.1.1.0/24"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Region where resources will be deployed | `string` | n/a | yes |
| <a name="input_nsg_name"></a> [nsg\_name](#input\_nsg\_name) | Name of the Network Security Group | `string` | `"camunda-aks-nsg"` | no |
| <a name="input_pe_subnet_address_prefix"></a> [pe\_subnet\_address\_prefix](#input\_pe\_subnet\_address\_prefix) | Address prefix for the private endpoint subnet | `list(string)` | <pre>[<br/>  "10.1.2.0/24"<br/>]</pre> | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the Azure resource group | `string` | n/a | yes |
| <a name="input_resource_prefix"></a> [resource\_prefix](#input\_resource\_prefix) | Prefix for resource names | `string` | `"camunda"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Address space for the virtual network | `list(string)` | <pre>[<br/>  "10.1.0.0/16"<br/>]</pre> | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aks_nsg_id"></a> [aks\_nsg\_id](#output\_aks\_nsg\_id) | ID of the Network Security Group for AKS |
| <a name="output_aks_subnet_id"></a> [aks\_subnet\_id](#output\_aks\_subnet\_id) | ID of the subnet where AKS is deployed |
| <a name="output_db_subnet_id"></a> [db\_subnet\_id](#output\_db\_subnet\_id) | Subnet ID for PostgreSQL Flexible Server |
| <a name="output_pe_subnet_id"></a> [pe\_subnet\_id](#output\_pe\_subnet\_id) | ID of the subnet for private endpoints |
| <a name="output_postgres_private_dns_zone_id"></a> [postgres\_private\_dns\_zone\_id](#output\_postgres\_private\_dns\_zone\_id) | Private DNS Zone ID for PostgreSQL Flexible Server |
| <a name="output_postgres_private_dns_zone_name"></a> [postgres\_private\_dns\_zone\_name](#output\_postgres\_private\_dns\_zone\_name) | Private DNS Zone name for PostgreSQL Flexible Server |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | ID of the virtual network |
<!-- END_TF_DOCS -->
