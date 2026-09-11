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
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Whether to apply cluster and instance changes immediately or during the next maintenance window. | `bool` | `true` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | If true, minor engine upgrades are applied automatically | `bool` | `true` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Number of days to retain automated Aurora backups. Minimum 1; set higher for production. Defaults to 7 to give a reasonable recovery window for dual-region failover scenarios. | `number` | `7` | no |
| <a name="input_ca_cert_identifier"></a> [ca\_cert\_identifier](#input\_ca\_cert\_identifier) | CA certificate identifier for DB instances | `string` | `"rds-ca-rsa2048-g1"` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | The name for the automatically created database | `string` | `"camunda"` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | The Aurora engine type: 'aurora-postgresql' or 'aurora-mysql' | `string` | `"aurora-postgresql"` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | DEPRECATED and non-functional. Use postgresql\_engine\_version or mysql\_engine\_version, whichever matches var.engine; the module selects between them. | `string` | `null` | no |
| <a name="input_extra_url_parameters"></a> [extra\_url\_parameters](#input\_extra\_url\_parameters) | Additional query parameters appended to the jdbc\_url, e.g. the failover plugin's { failoverTimeoutMs = "60000" } or the efm2 plugin's { failureDetectionTime = "15000" }. The parameters the module builds itself (wrapperPlugins, globalClusterInstanceHostPatterns, TLS mode) are reserved. | `map(string)` | `{}` | no |
| <a name="input_extra_wrapper_plugins"></a> [extra\_wrapper\_plugins](#input\_extra\_wrapper\_plugins) | Additional AWS Advanced JDBC Wrapper plugins to append to the jdbc\_url. The module always sets 'failover' (and 'iam' when iam\_auth\_enabled), so list only the extras here, e.g. ['readWriteSplitting']. Duplicates of the built-in plugins are ignored. The position a plugin takes in the list is not the execution order: the wrapper re-sorts the pipeline by built-in weight unless autoSortWrapperPluginOrder is disabled, which extra\_url\_parameters must not do. | `list(string)` | `[]` | no |
| <a name="input_global_cluster_identifier"></a> [global\_cluster\_identifier](#input\_global\_cluster\_identifier) | Identifier for the Aurora Global Database cluster | `string` | n/a | yes |
| <a name="input_iam_auth_enabled"></a> [iam\_auth\_enabled](#input\_iam\_auth\_enabled) | Enable IAM database authentication | `bool` | `true` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | The instance type of the Aurora instances | `string` | `"db.r6g.large"` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master\_password) | The password for the database admin user | `string` | n/a | yes |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | The username for the database admin user | `string` | n/a | yes |
| <a name="input_mysql_engine_version"></a> [mysql\_engine\_version](#input\_mysql\_engine\_version) | Aurora MySQL engine version, used when engine = aurora-mysql. Set this to pin a specific version for the MySQL path. | `string` | `"8.4.mysql_aurora.8.4.7"` | no |
| <a name="input_postgresql_engine_version"></a> [postgresql\_engine\_version](#input\_postgresql\_engine\_version) | Aurora PostgreSQL engine version, used when engine = aurora-postgresql. Set this to pin a specific version for the PostgreSQL path. | `string` | `"18.4"` | no |
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
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Whether to skip the final DB snapshot when the cluster is deleted. Set to false in production to retain a recovery point. | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to add to resources | `map(string)` | `{}` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_database_name"></a> [database\_name](#output\_database\_name) | The database created on the cluster; the path segment of the JDBC URL. |
| <a name="output_db_port"></a> [db\_port](#output\_db\_port) | The database port for the selected engine (5432 for PostgreSQL, 3306 for MySQL). |
| <a name="output_global_cluster_arn"></a> [global\_cluster\_arn](#output\_global\_cluster\_arn) | The ARN of the Aurora Global Database cluster |
| <a name="output_global_cluster_endpoint"></a> [global\_cluster\_endpoint](#output\_global\_cluster\_endpoint) | The writer endpoint for the Aurora Global Database cluster. This endpoint always points to the writer DB instance in the current primary cluster. |
| <a name="output_global_cluster_id"></a> [global\_cluster\_id](#output\_global\_cluster\_id) | The ID of the Aurora Global Database cluster |
| <a name="output_global_cluster_resource_id"></a> [global\_cluster\_resource\_id](#output\_global\_cluster\_resource\_id) | The resource ID of the Aurora Global Database cluster (used for IAM auth) |
| <a name="output_jdbc_subprotocol"></a> [jdbc\_subprotocol](#output\_jdbc\_subprotocol) | JDBC subprotocol for the selected engine ('postgresql' or 'mysql'), i.e. the segment after 'jdbc:aws-wrapper:'. |
| <a name="output_jdbc_url"></a> [jdbc\_url](#output\_jdbc\_url) | DEPRECATED — prefer composing the URL from the jdbc\_* component outputs below.<br/><br/>A fully assembled AWS Advanced JDBC Wrapper URL for the Aurora Global writer<br/>(engine-aware subprotocol and port, iam when enabled + failover plugins,<br/>globalClusterInstanceHostPatterns, TLS pinned). Kept for backward<br/>compatibility, but building the URL here forces a change to any connection<br/>property — a timeout, a pool setting — through this module and a redeploy of<br/>the infrastructure layer. Consumers should instead read jdbc\_subprotocol,<br/>global\_cluster\_endpoint, db\_port, database\_name and jdbc\_url\_parameters, and<br/>assemble the URL where the application is configured. This output will be<br/>removed in a future major. |
| <a name="output_jdbc_url_parameters"></a> [jdbc\_url\_parameters](#output\_jdbc\_url\_parameters) | Every query parameter for the JDBC URL, as a map: wrapperPlugins ('failover', plus 'iam' and 'initialConnection' when iam\_auth\_enabled, plus any extra\_wrapper\_plugins), globalClusterInstanceHostPatterns, the engine's TLS key (sslmode=require for PostgreSQL, sslMode=REQUIRED for MySQL — pinned rather than left to the driver default, which permits a plaintext downgrade), and any extra\_url\_parameters. Render it as '?' plus '&'-joined 'key=value' pairs; no entry carries a separator of its own. |
| <a name="output_primary_cluster_endpoint"></a> [primary\_cluster\_endpoint](#output\_primary\_cluster\_endpoint) | The writer endpoint of the primary Aurora cluster |
| <a name="output_primary_cluster_identifier"></a> [primary\_cluster\_identifier](#output\_primary\_cluster\_identifier) | The identifier of the primary Aurora cluster |
| <a name="output_primary_cluster_reader_endpoint"></a> [primary\_cluster\_reader\_endpoint](#output\_primary\_cluster\_reader\_endpoint) | The reader endpoint of the primary Aurora cluster |
| <a name="output_primary_cluster_resource_id"></a> [primary\_cluster\_resource\_id](#output\_primary\_cluster\_resource\_id) | The resource ID of the primary Aurora cluster (used for IAM auth) |
| <a name="output_secondary_cluster_endpoint"></a> [secondary\_cluster\_endpoint](#output\_secondary\_cluster\_endpoint) | The endpoint of the secondary Aurora cluster |
| <a name="output_secondary_cluster_identifier"></a> [secondary\_cluster\_identifier](#output\_secondary\_cluster\_identifier) | The identifier of the secondary Aurora cluster |
| <a name="output_secondary_cluster_reader_endpoint"></a> [secondary\_cluster\_reader\_endpoint](#output\_secondary\_cluster\_reader\_endpoint) | The reader endpoint of the secondary Aurora cluster |
| <a name="output_secondary_cluster_resource_id"></a> [secondary\_cluster\_resource\_id](#output\_secondary\_cluster\_resource\_id) | The resource ID of the secondary Aurora cluster (used for IAM auth) |
<!-- END_TF_DOCS -->
