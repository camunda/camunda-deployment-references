# Global database

Turns the standalone Aurora cluster of the storage stage into an Aurora Global Database, created from it, and adds a secondary cluster in a second region. Part of [growing to a second region](../../EVOLVE-DUAL.md). Its outputs have the shape of the storage stage's, so the Camunda stage takes them unchanged.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_secondary"></a> [secondary](#module\_secondary) | ../../../../modules/aurora-global-member | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.rds_db_connect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_rds_global_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_global_cluster) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | Name of the database Camunda uses (same as the storage stage) | `string` | `"camunda"` | no |
| <a name="input_db_users"></a> [db\_users](#input\_db\_users) | IAM database users. A connect policy covering both clusters is created per user. | `list(string)` | <pre>[<br/>  "camunda"<br/>]</pre> | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Engine version. Must equal the version of the existing cluster. | `string` | `"18.6"` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Let Terraform detach the members when destroying the global cluster. Dev and test only. The provider requires the attribute whenever the global cluster is created from an existing cluster, hence false rather than null. | `bool` | `false` | no |
| <a name="input_iam_auth_enabled"></a> [iam\_auth\_enabled](#input\_iam\_auth\_enabled) | IAM database authentication on the secondary (same as the primary) | `bool` | `true` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_private_subnet_ids_b"></a> [private\_subnet\_ids\_b](#input\_private\_subnet\_ids\_b) | Network stage output in region\_b: private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_region_a"></a> [region\_a](#input\_region\_a) | Region of the existing Aurora cluster (the primary of the global database) | `string` | n/a | yes |
| <a name="input_region_b"></a> [region\_b](#input\_region\_b) | Region of the secondary cluster | `string` | n/a | yes |
| <a name="input_secondary_instance_class"></a> [secondary\_instance\_class](#input\_secondary\_instance\_class) | Instance class of the secondary. Global databases do not support db.t3/db.t4g, and the primary must also be an r-class or serverless instance before the global cluster can be created. | `string` | `"db.r6g.large"` | no |
| <a name="input_secondary_num_instances"></a> [secondary\_num\_instances](#input\_secondary\_num\_instances) | Number of instances of the secondary cluster | `number` | `1` | no |
| <a name="input_source_cluster_arn"></a> [source\_cluster\_arn](#input\_source\_cluster\_arn) | Storage stage output cluster\_arn: the existing cluster, which becomes the primary | `string` | n/a | yes |
| <a name="input_source_cluster_endpoint"></a> [source\_cluster\_endpoint](#input\_source\_cluster\_endpoint) | Storage stage output secondary\_storage.host: writer endpoint of the existing cluster | `string` | n/a | yes |
| <a name="input_source_cluster_identifier"></a> [source\_cluster\_identifier](#input\_source\_cluster\_identifier) | Storage stage output cluster\_identifier | `string` | n/a | yes |
| <a name="input_source_cluster_resource_id"></a> [source\_cluster\_resource\_id](#input\_source\_cluster\_resource\_id) | Storage stage output cluster\_resource\_id | `string` | n/a | yes |
| <a name="input_vpc_cidr_a"></a> [vpc\_cidr\_a](#input\_vpc\_cidr\_a) | Network stage output in region\_a: VPC CIDR | `string` | n/a | yes |
| <a name="input_vpc_cidr_b"></a> [vpc\_cidr\_b](#input\_vpc\_cidr\_b) | Network stage output in region\_b: VPC CIDR | `string` | n/a | yes |
| <a name="input_vpc_id_a"></a> [vpc\_id\_a](#input\_vpc\_id\_a) | Network stage output in region\_a: VPC ID | `string` | n/a | yes |
| <a name="input_vpc_id_b"></a> [vpc\_id\_b](#input\_vpc\_id\_b) | Network stage output in region\_b: VPC ID | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_db_seed_done"></a> [db\_seed\_done](#output\_db\_seed\_done) | Placeholder so that the Camunda stage takes the same inputs as with the storage stage. The database users were created before the global cluster. |
| <a name="output_global_cluster_identifier"></a> [global\_cluster\_identifier](#output\_global\_cluster\_identifier) | Set it as global\_cluster\_identifier on the storage stage, so that Terraform does not plan to detach the cluster |
| <a name="output_rds_db_connect_policy_arns"></a> [rds\_db\_connect\_policy\_arns](#output\_rds\_db\_connect\_policy\_arns) | Per IAM database user: a policy that allows connecting to both clusters. Replace the single-cluster policy of the storage stage with it. |
| <a name="output_secondary_security_group_id"></a> [secondary\_security\_group\_id](#output\_secondary\_security\_group\_id) | Security group of the secondary cluster |
| <a name="output_secondary_storage"></a> [secondary\_storage](#output\_secondary\_storage) | Connection settings through the global writer endpoint |
<!-- END_TF_DOCS -->
