# aurora-global

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_db_subnet_group.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_db_subnet_group.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_kms_key.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_rds_cluster.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_cluster_instance.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_global_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_global_cluster) | resource |
| [aws_security_group.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [time_sleep.wait_for_primary](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | If true, minor engine upgrades are applied automatically | `bool` | `true` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Number of days to retain automated Aurora backups. Minimum 1; set higher for production. Defaults to 7 to give a reasonable recovery window for dual-region failover scenarios. | `number` | `7` | no |
| <a name="input_ca_cert_identifier"></a> [ca\_cert\_identifier](#input\_ca\_cert\_identifier) | CA certificate identifier for DB instances | `string` | `"rds-ca-rsa2048-g1"` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | The name for the automatically created database | `string` | `"camunda"` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | The engine type e.g. aurora-postgresql | `string` | `"aurora-postgresql"` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | The DB engine version for Postgres to use | `string` | `"17.9"` | no |
| <a name="input_global_cluster_identifier"></a> [global\_cluster\_identifier](#input\_global\_cluster\_identifier) | Identifier for the Aurora Global Database cluster | `string` | n/a | yes |
| <a name="input_iam_auth_enabled"></a> [iam\_auth\_enabled](#input\_iam\_auth\_enabled) | Enable IAM database authentication | `bool` | `true` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | The instance type of the Aurora instances | `string` | `"db.r6g.large"` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master\_password) | The password for the postgres admin user | `string` | n/a | yes |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | The username for the postgres admin user | `string` | n/a | yes |
| <a name="input_primary_availability_zones"></a> [primary\_availability\_zones](#input\_primary\_availability\_zones) | Availability zones for the primary cluster | `list(string)` | n/a | yes |
| <a name="input_primary_cidr_blocks"></a> [primary\_cidr\_blocks](#input\_primary\_cidr\_blocks) | CIDR blocks to allow access from/to the primary cluster | `list(string)` | n/a | yes |
| <a name="input_primary_cluster_name"></a> [primary\_cluster\_name](#input\_primary\_cluster\_name) | Identifier for the primary Aurora cluster | `string` | n/a | yes |
| <a name="input_primary_num_instances"></a> [primary\_num\_instances](#input\_primary\_num\_instances) | Number of instances in the primary cluster | `number` | `1` | no |
| <a name="input_primary_subnet_ids"></a> [primary\_subnet\_ids](#input\_primary\_subnet\_ids) | Subnet IDs for the primary cluster | `list(string)` | n/a | yes |
| <a name="input_primary_vpc_id"></a> [primary\_vpc\_id](#input\_primary\_vpc\_id) | VPC ID for the primary cluster | `string` | n/a | yes |
| <a name="input_secondary_cidr_blocks"></a> [secondary\_cidr\_blocks](#input\_secondary\_cidr\_blocks) | CIDR blocks to allow access from/to the secondary cluster | `list(string)` | n/a | yes |
| <a name="input_secondary_cluster_name"></a> [secondary\_cluster\_name](#input\_secondary\_cluster\_name) | Identifier for the secondary Aurora cluster | `string` | n/a | yes |
| <a name="input_secondary_num_instances"></a> [secondary\_num\_instances](#input\_secondary\_num\_instances) | Number of instances in the secondary cluster | `number` | `1` | no |
| <a name="input_secondary_subnet_ids"></a> [secondary\_subnet\_ids](#input\_secondary\_subnet\_ids) | Subnet IDs for the secondary cluster | `list(string)` | n/a | yes |
| <a name="input_secondary_vpc_id"></a> [secondary\_vpc\_id](#input\_secondary\_vpc\_id) | VPC ID for the secondary cluster | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to add to resources | `map(string)` | `{}` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_global_cluster_id"></a> [global\_cluster\_id](#output\_global\_cluster\_id) | The ID of the Aurora Global Database cluster |
| <a name="output_primary_cluster_endpoint"></a> [primary\_cluster\_endpoint](#output\_primary\_cluster\_endpoint) | The writer endpoint of the primary Aurora cluster |
| <a name="output_primary_cluster_identifier"></a> [primary\_cluster\_identifier](#output\_primary\_cluster\_identifier) | The identifier of the primary Aurora cluster |
| <a name="output_primary_cluster_reader_endpoint"></a> [primary\_cluster\_reader\_endpoint](#output\_primary\_cluster\_reader\_endpoint) | The reader endpoint of the primary Aurora cluster |
| <a name="output_primary_cluster_resource_id"></a> [primary\_cluster\_resource\_id](#output\_primary\_cluster\_resource\_id) | The resource ID of the primary Aurora cluster (used for IAM auth) |
| <a name="output_secondary_cluster_endpoint"></a> [secondary\_cluster\_endpoint](#output\_secondary\_cluster\_endpoint) | The endpoint of the secondary Aurora cluster |
| <a name="output_secondary_cluster_identifier"></a> [secondary\_cluster\_identifier](#output\_secondary\_cluster\_identifier) | The identifier of the secondary Aurora cluster |
| <a name="output_secondary_cluster_reader_endpoint"></a> [secondary\_cluster\_reader\_endpoint](#output\_secondary\_cluster\_reader\_endpoint) | The reader endpoint of the secondary Aurora cluster |
| <a name="output_secondary_cluster_resource_id"></a> [secondary\_cluster\_resource\_id](#output\_secondary\_cluster\_resource\_id) | The resource ID of the secondary Aurora cluster (used for IAM auth) |
<!-- END_TF_DOCS -->
