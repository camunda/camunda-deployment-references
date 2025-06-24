# postgres-db

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [azurerm_postgresql_flexible_server.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server) | resource |
| [azurerm_private_endpoint.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | Administrator password for PostgreSQL Flexible Server | `string` | n/a | yes |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Administrator login name for PostgreSQL Flexible Server | `string` | n/a | yes |
| <a name="input_backup_retention_days"></a> [backup\_retention\_days](#input\_backup\_retention\_days) | Backup retention period in days (7-35) | `number` | `7` | no |
| <a name="input_enable_geo_redundant_backup"></a> [enable\_geo\_redundant\_backup](#input\_enable\_geo\_redundant\_backup) | Enable geo-redundant backup | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region | `string` | n/a | yes |
| <a name="input_postgres_version"></a> [postgres\_version](#input\_postgres\_version) | PostgreSQL version | `string` | `"15"` | no |
| <a name="input_private_dns_zone_id"></a> [private\_dns\_zone\_id](#input\_private\_dns\_zone\_id) | Private DNS Zone ID for PostgreSQL | `string` | n/a | yes |
| <a name="input_private_endpoint_subnet_id"></a> [private\_endpoint\_subnet\_id](#input\_private\_endpoint\_subnet\_id) | Subnet ID for the PostgreSQL private endpoint | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group name for PostgreSQL Flexible Server | `string` | n/a | yes |
| <a name="input_server_name"></a> [server\_name](#input\_server\_name) | Name for the PostgreSQL Flexible Server instance | `string` | n/a | yes |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | SKU name for the PostgreSQL Flexible Server | `string` | `"B_Standard_B1ms"` | no |
| <a name="input_standby_availability_zone"></a> [standby\_availability\_zone](#input\_standby\_availability\_zone) | Availability Zone for the standby instance (must differ from primary) | `string` | `"2"` | no |
| <a name="input_storage_mb"></a> [storage\_mb](#input\_storage\_mb) | Storage size in MB | `number` | `32768` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | Primary Availability Zone for the PostgreSQL server | `string` | `"1"` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_username"></a> [admin\_username](#output\_admin\_username) | The administrator username for the PostgreSQL Flexible Server |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | The fully qualified domain name of the PostgreSQL Flexible Server |
| <a name="output_server_id"></a> [server\_id](#output\_server\_id) | The ID of the PostgreSQL Flexible Server |
<!-- END_TF_DOCS -->
