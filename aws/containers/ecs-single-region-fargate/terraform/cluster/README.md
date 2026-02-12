# terraform

This directory contains the Terraform implementation for the ECS single-region (Fargate) reference architecture.

- Architecture & design documentation: `../README.md`
- Auto-generated Terraform inputs/outputs: see below.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_connectors"></a> [connectors](#module\_connectors) | ../../../../modules/ecs/fargate/connectors | n/a |
| <a name="module_orchestration_cluster"></a> [orchestration\_cluster](#module\_orchestration\_cluster) | ../../../../modules/ecs/fargate/orchestration-cluster | n/a |
| <a name="module_postgresql"></a> [postgresql](#module\_postgresql) | ../../../../modules/aurora | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | v6.6.0 |
## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.db_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_task_definition.db_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.ecs_task_secrets_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.rds_db_connect_camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.registry_secrets_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_backup_access_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_execution_registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_execution_task_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.s3_bucket_key_alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.s3_bucket_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_lb.grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http_management](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_webapp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_s3_bucket.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_secretsmanager_secret.connectors_client_auth_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.db_admin_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.orchestration_admin_user_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.registry_credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.connectors_client_auth_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.db_admin_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.orchestration_admin_user_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.registry_credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.allow_necessary_camunda_ports_within_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_package_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [null_resource.run_db_seed_task](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_password.admin_user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.connectors_user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.db_admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eips.current_usage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eips) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_servicequotas_service_quota.elastic_ip_quota](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/servicequotas_service_quota) | data source |
| [aws_vpcs.current_vpcs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpcs) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_blocks"></a> [cidr\_blocks](#input\_cidr\_blocks) | The CIDR block to use for the VPC | `string` | `"10.190.0.0/16"` | no |
| <a name="input_db_admin_password"></a> [db\_admin\_password](#input\_db\_admin\_password) | Optional override for the Aurora PostgreSQL admin password. If empty, a random password is generated and stored in Secrets Manager. | `string` | `""` | no |
| <a name="input_db_admin_username"></a> [db\_admin\_username](#input\_db\_admin\_username) | Admin username for the Aurora PostgreSQL cluster (demo default; use Secrets Manager in production) | `string` | `"camunda_admin"` | no |
| <a name="input_db_iam_auth_enabled"></a> [db\_iam\_auth\_enabled](#input\_db\_iam\_auth\_enabled) | Enable IAM database authentication on the Aurora cluster | `bool` | `true` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Database name used by Camunda components | `string` | `"camunda"` | no |
| <a name="input_db_seed_enabled"></a> [db\_seed\_enabled](#input\_db\_seed\_enabled) | Run a one-time ECS task to create/grant IAM DB users (uses db\_admin\_username/password) | `bool` | `true` | no |
| <a name="input_db_seed_iam_usernames"></a> [db\_seed\_iam\_usernames](#input\_db\_seed\_iam\_usernames) | Database users to create and grant rds\_iam + privileges for (used for IAM DB auth) | `list(string)` | <pre>[<br/>  "camunda"<br/>]</pre> | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_limit_access_to_cidrs"></a> [limit\_access\_to\_cidrs](#input\_limit\_access\_to\_cidrs) | List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_ports"></a> [ports](#input\_ports) | The ports to open for the security groups within the VPC | `map(number)` | <pre>{<br/>  "camunda_metrics_endpoint": 9600,<br/>  "camunda_web_ui": 8080,<br/>  "postgresql": 5432,<br/>  "zeebe_broker_network_command_api_port": 26501,<br/>  "zeebe_gateway_cluster_port": 26502,<br/>  "zeebe_gateway_network_port": 26500<br/>}</pre> | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for names of resources | `string` | `"camunda"` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | (Optional) The password for the container registry (e.g., Docker Hub) | `string` | `""` | no |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | (Optional) The username for the container registry (e.g., Docker Hub) | `string` | `""` | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Optional existing KMS key ARN to use for encrypting Secrets Manager secrets. If empty, this stack will create and manage a CMK. | `string` | `""` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_user_password"></a> [admin\_user\_password](#output\_admin\_user\_password) | The admin password for Camunda. Easy access purposes, saved in Secrets Manager. |
| <a name="output_alb_endpoint"></a> [alb\_endpoint](#output\_alb\_endpoint) | (Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp. |
| <a name="output_nlb_endpoint"></a> [nlb\_endpoint](#output\_nlb\_endpoint) | (Optional) The DNS name of the Network Load Balancer (NLB) to access the Camunda Core. |
<!-- END_TF_DOCS -->
