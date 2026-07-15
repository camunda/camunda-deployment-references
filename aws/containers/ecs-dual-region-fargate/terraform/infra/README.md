# infra

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_aurora_global"></a> [aurora\_global](#module\_aurora\_global) | ../../../../modules/aurora-global | n/a |
| <a name="module_opensearch_region_0"></a> [opensearch\_region\_0](#module\_opensearch\_region\_0) | ../../../../modules/opensearch | n/a |
| <a name="module_opensearch_region_1"></a> [opensearch\_region\_1](#module\_opensearch\_region\_1) | ../../../../modules/opensearch | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.db_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_task_definition.db_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.ecs_task_secrets_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ecs_task_secrets_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.rds_db_connect_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.rds_db_connect_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_backup_access_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_backup_access_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_task_execution_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_secrets_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_secrets_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.s3_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.s3_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.secrets_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.secrets_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.s3_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.s3_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.secrets_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.secrets_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_lb.alb_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.alb_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.nlb_grpc_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.nlb_grpc_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.nlb_raft_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.nlb_raft_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http_management_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_management_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_webapp_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_webapp_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_s3_bucket.backup_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.backup_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.backup_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.backup_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.backup_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.backup_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.backup_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.backup_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_secretsmanager_secret.admin_user_password_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.admin_user_password_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.connectors_password_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.connectors_password_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.db_admin_password_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.registry_credentials_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.registry_credentials_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.admin_user_password_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.admin_user_password_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.connectors_password_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.connectors_password_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.db_admin_password_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.registry_credentials_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.registry_credentials_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.camunda_ports_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.camunda_ports_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.package_80_443_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.package_80_443_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.remote_access_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.remote_access_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [null_resource.run_db_seed_task](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_id.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_password.admin_user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.connectors_user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.db_admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_region.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.region_0_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnet.region_1_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [terraform_remote_state.vpc](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS Profile to use (null = use default credential chain) | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster to prefix resources | `string` | n/a | yes |
| <a name="input_db_admin_password"></a> [db\_admin\_password](#input\_db\_admin\_password) | Optional override for the Aurora PostgreSQL admin password. If empty, a random password is generated. | `string` | `""` | no |
| <a name="input_db_admin_username"></a> [db\_admin\_username](#input\_db\_admin\_username) | Admin username for the Aurora PostgreSQL cluster | `string` | `"camunda_admin"` | no |
| <a name="input_db_iam_auth_enabled"></a> [db\_iam\_auth\_enabled](#input\_db\_iam\_auth\_enabled) | Enable IAM database authentication on the Aurora cluster | `bool` | `true` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Database name used by Camunda components | `string` | `"camunda"` | no |
| <a name="input_db_seed_enabled"></a> [db\_seed\_enabled](#input\_db\_seed\_enabled) | Run a one-time ECS task to create/grant IAM DB users | `bool` | `true` | no |
| <a name="input_db_seed_iam_usernames"></a> [db\_seed\_iam\_usernames](#input\_db\_seed\_iam\_usernames) | Database users to create and grant rds\_iam + privileges for | `list(string)` | <pre>[<br/>  "camunda"<br/>]</pre> | no |
| <a name="input_db_seed_run_id"></a> [db\_seed\_run\_id](#input\_db\_seed\_run\_id) | Increment this value to force the DB seed task to re-run on the next apply (e.g. '1' → '2'). All SQL is idempotent so re-running is safe. | `string` | `"1"` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_limit_access_to_cidrs"></a> [limit\_access\_to\_cidrs](#input\_limit\_access\_to\_cidrs) | List of CIDR blocks to allow access to LoadBalancers | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_ports"></a> [ports](#input\_ports) | The ports to open for the security groups within the VPC | `map(number)` | <pre>{<br/>  "camunda_metrics_endpoint": 9600,<br/>  "camunda_web_ui": 8080,<br/>  "postgresql": 5432,<br/>  "zeebe_broker_network_command_api_port": 26501,<br/>  "zeebe_gateway_cluster_port": 26502,<br/>  "zeebe_gateway_network_port": 26500<br/>}</pre> | no |
| <a name="input_region_0"></a> [region\_0](#input\_region\_0) | AWS region for the primary (owner) cluster | `string` | `"eu-west-2"` | no |
| <a name="input_region_1"></a> [region\_1](#input\_region\_1) | AWS region for the secondary (accepter) cluster | `string` | `"eu-west-3"` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | (Optional) The password for the container registry | `string` | `""` | no |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | (Optional) The username for the container registry | `string` | `""` | no |
| <a name="input_s3_force_destroy"></a> [s3\_force\_destroy](#input\_s3\_force\_destroy) | Allow Terraform to destroy S3 backup buckets even if they contain objects. Defaults to true because this is a reference / demo architecture and `terraform destroy` should clean up without manual S3 cleanup. Set to false before running a real workload through it so Terraform refuses to drop backup data. | `bool` | `true` | no |
| <a name="input_secondary_storage_type"></a> [secondary\_storage\_type](#input\_secondary\_storage\_type) | Camunda secondary storage: 'rdbms' (Aurora Global) or 'opensearch' | `string` | `"rdbms"` | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Optional existing KMS key ARN for region 0. If empty, a CMK is created. | `string` | `""` | no |
| <a name="input_secrets_kms_key_arn_accepter"></a> [secrets\_kms\_key\_arn\_accepter](#input\_secrets\_kms\_key\_arn\_accepter) | Optional existing KMS key ARN for region 1. If empty, a CMK is created. | `string` | `""` | no |
| <a name="input_terraform_backend_bucket"></a> [terraform\_backend\_bucket](#input\_terraform\_backend\_bucket) | S3 bucket name storing Terraform state for all layers | `string` | n/a | yes |
| <a name="input_terraform_backend_key_prefix"></a> [terraform\_backend\_key\_prefix](#input\_terraform\_backend\_key\_prefix) | S3 key prefix shared by all layers. E.g. 'aws/containers/ecs-dual-region-fargate/my-cluster/' yields 's3://<bucket>/<prefix>vpc/terraform.tfstate' | `string` | n/a | yes |
| <a name="input_terraform_backend_region"></a> [terraform\_backend\_region](#input\_terraform\_backend\_region) | AWS region of the S3 bucket storing Terraform state (may differ from the deployment regions) | `string` | `"eu-central-1"` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admin_user_password"></a> [admin\_user\_password](#output\_admin\_user\_password) | The admin password for Camunda |
| <a name="output_admin_user_password_secret_region_0_arn"></a> [admin\_user\_password\_secret\_region\_0\_arn](#output\_admin\_user\_password\_secret\_region\_0\_arn) | n/a |
| <a name="output_admin_user_password_secret_region_1_arn"></a> [admin\_user\_password\_secret\_region\_1\_arn](#output\_admin\_user\_password\_secret\_region\_1\_arn) | n/a |
| <a name="output_alb_listener_http_management_region_0_arn"></a> [alb\_listener\_http\_management\_region\_0\_arn](#output\_alb\_listener\_http\_management\_region\_0\_arn) | n/a |
| <a name="output_alb_listener_http_management_region_1_arn"></a> [alb\_listener\_http\_management\_region\_1\_arn](#output\_alb\_listener\_http\_management\_region\_1\_arn) | n/a |
| <a name="output_alb_listener_http_webapp_region_0_arn"></a> [alb\_listener\_http\_webapp\_region\_0\_arn](#output\_alb\_listener\_http\_webapp\_region\_0\_arn) | n/a |
| <a name="output_alb_listener_http_webapp_region_1_arn"></a> [alb\_listener\_http\_webapp\_region\_1\_arn](#output\_alb\_listener\_http\_webapp\_region\_1\_arn) | n/a |
| <a name="output_aurora_global_cluster_id"></a> [aurora\_global\_cluster\_id](#output\_aurora\_global\_cluster\_id) | The ID of the Aurora Global Database cluster |
| <a name="output_aurora_global_writer_endpoint"></a> [aurora\_global\_writer\_endpoint](#output\_aurora\_global\_writer\_endpoint) | The global writer endpoint of the Aurora Global DB. Always routes to the current writer across regions after failover. |
| <a name="output_aurora_primary_cluster_endpoint"></a> [aurora\_primary\_cluster\_endpoint](#output\_aurora\_primary\_cluster\_endpoint) | The regional writer endpoint of the primary Aurora cluster (region 0). Used to derive globalClusterInstanceHostPatterns for the AWS JDBC wrapper. |
| <a name="output_aurora_primary_cluster_identifier"></a> [aurora\_primary\_cluster\_identifier](#output\_aurora\_primary\_cluster\_identifier) | n/a |
| <a name="output_aurora_secondary_cluster_identifier"></a> [aurora\_secondary\_cluster\_identifier](#output\_aurora\_secondary\_cluster\_identifier) | n/a |
| <a name="output_aurora_secondary_endpoint"></a> [aurora\_secondary\_endpoint](#output\_aurora\_secondary\_endpoint) | n/a |
| <a name="output_backup_bucket_region_0_name"></a> [backup\_bucket\_region\_0\_name](#output\_backup\_bucket\_region\_0\_name) | n/a |
| <a name="output_backup_bucket_region_1_name"></a> [backup\_bucket\_region\_1\_name](#output\_backup\_bucket\_region\_1\_name) | n/a |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | n/a |
| <a name="output_connectors_password_secret_region_0_arn"></a> [connectors\_password\_secret\_region\_0\_arn](#output\_connectors\_password\_secret\_region\_0\_arn) | n/a |
| <a name="output_connectors_password_secret_region_1_arn"></a> [connectors\_password\_secret\_region\_1\_arn](#output\_connectors\_password\_secret\_region\_1\_arn) | n/a |
| <a name="output_db_admin_username"></a> [db\_admin\_username](#output\_db\_admin\_username) | n/a |
| <a name="output_db_name"></a> [db\_name](#output\_db\_name) | n/a |
| <a name="output_ecs_cluster_region_0_id"></a> [ecs\_cluster\_region\_0\_id](#output\_ecs\_cluster\_region\_0\_id) | n/a |
| <a name="output_ecs_cluster_region_1_id"></a> [ecs\_cluster\_region\_1\_id](#output\_ecs\_cluster\_region\_1\_id) | n/a |
| <a name="output_ecs_task_execution_role_region_0_arn"></a> [ecs\_task\_execution\_role\_region\_0\_arn](#output\_ecs\_task\_execution\_role\_region\_0\_arn) | n/a |
| <a name="output_ecs_task_execution_role_region_1_arn"></a> [ecs\_task\_execution\_role\_region\_1\_arn](#output\_ecs\_task\_execution\_role\_region\_1\_arn) | n/a |
| <a name="output_nlb_grpc_region_0_arn"></a> [nlb\_grpc\_region\_0\_arn](#output\_nlb\_grpc\_region\_0\_arn) | n/a |
| <a name="output_nlb_grpc_region_1_arn"></a> [nlb\_grpc\_region\_1\_arn](#output\_nlb\_grpc\_region\_1\_arn) | n/a |
| <a name="output_nlb_raft_region_0_arn"></a> [nlb\_raft\_region\_0\_arn](#output\_nlb\_raft\_region\_0\_arn) | n/a |
| <a name="output_nlb_raft_region_0_dns_name"></a> [nlb\_raft\_region\_0\_dns\_name](#output\_nlb\_raft\_region\_0\_dns\_name) | n/a |
| <a name="output_nlb_raft_region_1_arn"></a> [nlb\_raft\_region\_1\_arn](#output\_nlb\_raft\_region\_1\_arn) | n/a |
| <a name="output_nlb_raft_region_1_dns_name"></a> [nlb\_raft\_region\_1\_dns\_name](#output\_nlb\_raft\_region\_1\_dns\_name) | n/a |
| <a name="output_opensearch_region_0_endpoint"></a> [opensearch\_region\_0\_endpoint](#output\_opensearch\_region\_0\_endpoint) | The endpoint of the OpenSearch domain in region 0 |
| <a name="output_opensearch_region_1_endpoint"></a> [opensearch\_region\_1\_endpoint](#output\_opensearch\_region\_1\_endpoint) | The endpoint of the OpenSearch domain in region 1 |
| <a name="output_rds_db_connect_policy_region_0_arn"></a> [rds\_db\_connect\_policy\_region\_0\_arn](#output\_rds\_db\_connect\_policy\_region\_0\_arn) | n/a |
| <a name="output_rds_db_connect_policy_region_1_arn"></a> [rds\_db\_connect\_policy\_region\_1\_arn](#output\_rds\_db\_connect\_policy\_region\_1\_arn) | n/a |
| <a name="output_region_0"></a> [region\_0](#output\_region\_0) | n/a |
| <a name="output_region_0_alb_endpoint"></a> [region\_0\_alb\_endpoint](#output\_region\_0\_alb\_endpoint) | The DNS name of the ALB in region 0 (HTTP/REST access) |
| <a name="output_region_0_nlb_grpc_endpoint"></a> [region\_0\_nlb\_grpc\_endpoint](#output\_region\_0\_nlb\_grpc\_endpoint) | The DNS name of the external NLB in region 0 (gRPC access) |
| <a name="output_region_1"></a> [region\_1](#output\_region\_1) | n/a |
| <a name="output_region_1_alb_endpoint"></a> [region\_1\_alb\_endpoint](#output\_region\_1\_alb\_endpoint) | The DNS name of the ALB in region 1 (HTTP/REST access) |
| <a name="output_region_1_nlb_grpc_endpoint"></a> [region\_1\_nlb\_grpc\_endpoint](#output\_region\_1\_nlb\_grpc\_endpoint) | The DNS name of the external NLB in region 1 (gRPC access) |
| <a name="output_registry_credentials_region_0_arn"></a> [registry\_credentials\_region\_0\_arn](#output\_registry\_credentials\_region\_0\_arn) | n/a |
| <a name="output_registry_credentials_region_1_arn"></a> [registry\_credentials\_region\_1\_arn](#output\_registry\_credentials\_region\_1\_arn) | n/a |
| <a name="output_s3_backup_access_policy_region_0_arn"></a> [s3\_backup\_access\_policy\_region\_0\_arn](#output\_s3\_backup\_access\_policy\_region\_0\_arn) | n/a |
| <a name="output_s3_backup_access_policy_region_1_arn"></a> [s3\_backup\_access\_policy\_region\_1\_arn](#output\_s3\_backup\_access\_policy\_region\_1\_arn) | n/a |
| <a name="output_s3_force_destroy"></a> [s3\_force\_destroy](#output\_s3\_force\_destroy) | n/a |
| <a name="output_secondary_storage_type"></a> [secondary\_storage\_type](#output\_secondary\_storage\_type) | n/a |
| <a name="output_sg_camunda_ports_region_0_id"></a> [sg\_camunda\_ports\_region\_0\_id](#output\_sg\_camunda\_ports\_region\_0\_id) | n/a |
| <a name="output_sg_camunda_ports_region_1_id"></a> [sg\_camunda\_ports\_region\_1\_id](#output\_sg\_camunda\_ports\_region\_1\_id) | n/a |
| <a name="output_sg_efs_region_0_id"></a> [sg\_efs\_region\_0\_id](#output\_sg\_efs\_region\_0\_id) | n/a |
| <a name="output_sg_efs_region_1_id"></a> [sg\_efs\_region\_1\_id](#output\_sg\_efs\_region\_1\_id) | n/a |
| <a name="output_sg_package_80_443_region_0_id"></a> [sg\_package\_80\_443\_region\_0\_id](#output\_sg\_package\_80\_443\_region\_0\_id) | n/a |
| <a name="output_sg_package_80_443_region_1_id"></a> [sg\_package\_80\_443\_region\_1\_id](#output\_sg\_package\_80\_443\_region\_1\_id) | n/a |
| <a name="output_vpc_region_0_id"></a> [vpc\_region\_0\_id](#output\_vpc\_region\_0\_id) | n/a |
| <a name="output_vpc_region_0_private_subnets"></a> [vpc\_region\_0\_private\_subnets](#output\_vpc\_region\_0\_private\_subnets) | n/a |
| <a name="output_vpc_region_1_id"></a> [vpc\_region\_1\_id](#output\_vpc\_region\_1\_id) | n/a |
| <a name="output_vpc_region_1_private_subnets"></a> [vpc\_region\_1\_private\_subnets](#output\_vpc\_region\_1\_private\_subnets) | n/a |
<!-- END_TF_DOCS -->
