# aurora-global-member

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_rds_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | CIDR blocks allowed to reach the database. Must contain every participating region VPC CIDR, because brokers in any region connect to the current global writer. | `list(string)` | n/a | yes |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Whether modifications are applied immediately instead of during the maintenance window | `bool` | `true` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | Whether minor engine upgrades are applied automatically during the maintenance window | `bool` | `true` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones of the regional cluster. Only honoured on the primary member. | `list(string)` | `null` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Number of days automated backups are retained | `number` | `7` | no |
| <a name="input_ca_cert_identifier"></a> [ca\_cert\_identifier](#input\_ca\_cert\_identifier) | Certificate authority used by the cluster instances | `string` | `"rds-ca-rsa2048-g1"` | no |
| <a name="input_cluster_identifier"></a> [cluster\_identifier](#input\_cluster\_identifier) | Identifier of the regional Aurora cluster. Lowercase letters, digits and hyphens, starting with a letter and not ending with one. | `string` | n/a | yes |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | Name of the initial database. Only honoured on the primary member. | `string` | `"camunda"` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | Aurora engine type. Only aurora-postgresql is exercised by the reference architecture. | `string` | `"aurora-postgresql"` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Aurora engine version. Must match the version of the global cluster. | `string` | `"17.9"` | no |
| <a name="input_global_cluster_identifier"></a> [global\_cluster\_identifier](#input\_global\_cluster\_identifier) | ID of the aws\_rds\_global\_cluster this regional cluster joins | `string` | n/a | yes |
| <a name="input_iam_auth_enabled"></a> [iam\_auth\_enabled](#input\_iam\_auth\_enabled) | Whether IAM database authentication is enabled. Recommended: the AWS JDBC wrapper iam plugin removes the need to distribute a password. | `bool` | `true` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Instance class of the Aurora cluster instances | `string` | `"db.r6g.large"` | no |
| <a name="input_is_primary"></a> [is\_primary](#input\_is\_primary) | Whether this member is the writer (primary) of the global cluster. Exactly one member must set this to true. | `bool` | `false` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master\_password) | Master password. Only honoured on the primary member. | `string` | `null` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master username. Only honoured on the primary member. | `string` | `null` | no |
| <a name="input_num_instances"></a> [num\_instances](#input\_num\_instances) | Number of Aurora instances in this region. Use at least 2 in production for intra-region failover. | `number` | `1` | no |
| <a name="input_port"></a> [port](#input\_port) | Database port | `number` | `5432` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Whether the final snapshot is skipped on destroy. Kept true for the reference architecture, which is disposable. | `bool` | `true` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs used for the Aurora DB subnet group | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource created by this module | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC the Aurora security group is created in | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the regional Aurora cluster |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | Identifier of the regional Aurora cluster |
| <a name="output_cluster_resource_id"></a> [cluster\_resource\_id](#output\_cluster\_resource\_id) | Immutable resource ID of the cluster, used to build rds-db:connect IAM policies |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Writer endpoint of the regional cluster |
| <a name="output_instance_host_pattern"></a> [instance\_host\_pattern](#output\_instance\_host\_pattern) | Instance host pattern for the AWS Advanced JDBC Wrapper<br/>globalClusterInstanceHostPatterns parameter. The `?` placeholder is<br/>substituted with the instance identifier by the driver, which is how it<br/>enumerates the instances of every region after a global failover. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Reader endpoint of the regional cluster |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the security group attached to the regional cluster |
<!-- END_TF_DOCS -->
