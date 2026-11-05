# Secondary storage layer

Aurora PostgreSQL for the Orchestration Cluster's RDBMS secondary storage, the database admin secret and a one-time seed task that creates the IAM-authenticated database users.

To turn the cluster into an Aurora Global Database later, see the evolution runbook: Global Databases do not support `db.t3`/`db.t4g`, so start from an r-class `db_instance_class` if you plan to grow.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_aurora"></a> [aurora](#module\_aurora) | ../../../../modules/aurora | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.db_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_task_definition.db_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.database_passwords_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.db_admin_password_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.rds_db_connect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role_policy_attachment.database_passwords_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.db_admin_password_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_secretsmanager_secret.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.db_admin_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.db_admin_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [null_resource.run_db_seed_task](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_password.database](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.db_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_cidr_blocks"></a> [additional\_cidr\_blocks](#input\_additional\_cidr\_blocks) | CIDR blocks of other VPCs, for example the second region, allowed to reach the database. Empty for a single region. | `list(string)` | `[]` | no |
| <a name="input_databases"></a> [databases](#input\_databases) | Further databases on the cluster for components that need their own, such as the OIDC provider, Management Identity, and Camunda Hub. Each gets a role and a database. auth = iam: the role authenticates with an IAM token (no password). auth = password: a random password is generated and stored in Secrets Manager. | <pre>map(object({<br/>    database_name = string<br/>    username      = string<br/>    auth          = optional(string, "iam")<br/>  }))</pre> | `{}` | no |
| <a name="input_db_admin_password"></a> [db\_admin\_password](#input\_db\_admin\_password) | Admin password. When empty, a random one is generated and stored in Secrets Manager. | `string` | `""` | no |
| <a name="input_db_admin_username"></a> [db\_admin\_username](#input\_db\_admin\_username) | Admin user of the Aurora cluster | `string` | `"camunda_admin"` | no |
| <a name="input_db_iam_auth_enabled"></a> [db\_iam\_auth\_enabled](#input\_db\_iam\_auth\_enabled) | Enable IAM database authentication. Camunda connects through the AWS JDBC wrapper with the iam plugin. | `bool` | `true` | no |
| <a name="input_db_instance_class"></a> [db\_instance\_class](#input\_db\_instance\_class) | Instance class of the Aurora instance. Aurora Global Databases do not support db.t3/db.t4g: pick an r-class (for example db.r6g.large) or db.serverless if you plan to add a second region. | `string` | `"db.t3.medium"` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Name of the database Camunda uses | `string` | `"camunda"` | no |
| <a name="input_db_num_instances"></a> [db\_num\_instances](#input\_db\_num\_instances) | Number of Aurora instances | `number` | `1` | no |
| <a name="input_db_seed_enabled"></a> [db\_seed\_enabled](#input\_db\_seed\_enabled) | Run a one-time ECS task that creates the IAM-authenticated database users. Needs the AWS CLI where Terraform runs. | `bool` | `true` | no |
| <a name="input_db_seed_iam_usernames"></a> [db\_seed\_iam\_usernames](#input\_db\_seed\_iam\_usernames) | Database users created for IAM authentication | `list(string)` | <pre>[<br/>  "camunda"<br/>]</pre> | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_ecs_cluster_arn"></a> [ecs\_cluster\_arn](#input\_ecs\_cluster\_arn) | Compute layer output: ARN of the ECS cluster that runs the one-time database seed task | `string` | n/a | yes |
| <a name="input_global_cluster_identifier"></a> [global\_cluster\_identifier](#input\_global\_cluster\_identifier) | Set once the cluster has been attached to an Aurora Global Database, so that Terraform does not plan to detach it. Leave null for a standalone cluster. | `string` | `null` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Network layer output: private subnet IDs (at least 3, distinct availability zones) | `list(string)` | n/a | yes |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Compute layer output: KMS key that encrypts the secrets | `string` | n/a | yes |
| <a name="input_seed_security_group_ids"></a> [seed\_security\_group\_ids](#input\_seed\_security\_group\_ids) | Compute layer outputs: security groups of the seed task (camunda\_ports\_security\_group\_id and egress\_security\_group\_id) | `list(string)` | n/a | yes |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | Compute layer output: ARN of the ECS task execution role | `string` | n/a | yes |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Compute layer output: name of the ECS task execution role. The database admin secret read policy is attached to it. | `string` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | Network layer output: CIDR block of the VPC, allowed to reach the database | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Network layer output: ID of the VPC | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the Aurora cluster. The global-database root uses it as the source of the global cluster. |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | Aurora cluster identifier. Use it as source\_db\_cluster\_identifier when creating a global cluster from this one. |
| <a name="output_cluster_resource_id"></a> [cluster\_resource\_id](#output\_cluster\_resource\_id) | Resource ID of the Aurora cluster, used in rds-db:connect policies |
| <a name="output_databases"></a> [databases](#output\_databases) | Per further database: its connection settings. Components read their database from here: the JDBC URL, the role, the password secret (auth = password) or the connect policy to attach to the task role (auth = iam). |
| <a name="output_db_seed_done"></a> [db\_seed\_done](#output\_db\_seed\_done) | Changes once the seed task has run. Pass it to the Camunda layer so that it starts after the database users exist. |
| <a name="output_rds_db_connect_policy_arns"></a> [rds\_db\_connect\_policy\_arns](#output\_rds\_db\_connect\_policy\_arns) | Per IAM database user: the policy that allows connecting as that user; attach it to the task role |
| <a name="output_secondary_storage"></a> [secondary\_storage](#output\_secondary\_storage) | Connection settings of the secondary storage |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group of the Aurora cluster |
<!-- END_TF_DOCS -->
