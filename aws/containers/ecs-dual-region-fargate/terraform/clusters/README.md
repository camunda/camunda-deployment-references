# clusters

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_aurora_global"></a> [aurora\_global](#module\_aurora\_global) | ../../../../modules/aurora-global | n/a |
| <a name="module_connectors_region_0"></a> [connectors\_region\_0](#module\_connectors\_region\_0) | ../../../../modules/ecs/fargate/connectors | n/a |
| <a name="module_connectors_region_1"></a> [connectors\_region\_1](#module\_connectors\_region\_1) | ../../../../modules/ecs/fargate/connectors | n/a |
| <a name="module_opensearch_region_0"></a> [opensearch\_region\_0](#module\_opensearch\_region\_0) | ../../../../modules/opensearch | n/a |
| <a name="module_opensearch_region_1"></a> [opensearch\_region\_1](#module\_opensearch\_region\_1) | ../../../../modules/opensearch | n/a |
| <a name="module_orchestration_cluster_region_0"></a> [orchestration\_cluster\_region\_0](#module\_orchestration\_cluster\_region\_0) | ../../../../modules/ecs/fargate/orchestration-cluster | n/a |
| <a name="module_orchestration_cluster_region_1"></a> [orchestration\_cluster\_region\_1](#module\_orchestration\_cluster\_region\_1) | ../../../../modules/ecs/fargate/orchestration-cluster | n/a |
| <a name="module_transit_gateway"></a> [transit\_gateway](#module\_transit\_gateway) | ../../../../modules/transit-gateway | n/a |
| <a name="module_vpc_region_0"></a> [vpc\_region\_0](#module\_vpc\_region\_0) | terraform-aws-modules/vpc/aws | v6.6.1 |
| <a name="module_vpc_region_1"></a> [vpc\_region\_1](#module\_vpc\_region\_1) | terraform-aws-modules/vpc/aws | v6.6.1 |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.db_seed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ec2_transit_gateway_route.region_0_to_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route.region_1_to_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
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
| [aws_route.region_0_private_to_region_1_peering](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.region_0_private_to_region_1_tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.region_1_private_to_region_0_peering](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.region_1_private_to_region_0_tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route53_resolver_endpoint.inbound_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.inbound_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_rule.region_0_to_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule) | resource |
| [aws_route53_resolver_rule.region_1_to_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule) | resource |
| [aws_route53_resolver_rule_association.region_0_to_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule_association) | resource |
| [aws_route53_resolver_rule_association.region_1_to_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule_association) | resource |
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
| [aws_security_group.dns_resolver_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.dns_resolver_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.package_80_443_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.package_80_443_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.remote_access_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.remote_access_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_peering_connection.cross_region](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [aws_vpc_peering_connection_accepter.cross_region](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_accepter) | resource |
| [aws_vpc_peering_connection_options.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_options) | resource |
| [aws_vpc_peering_connection_options.requester](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_options) | resource |
| [null_resource.run_db_seed_task](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_id.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_password.admin_user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.connectors_user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.db_admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_availability_zones.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_availability_zones.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_region.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS Profile to use (null = use default credential chain) | `string` | `null` | no |
| <a name="input_camunda_image"></a> [camunda\_image](#input\_camunda\_image) | Container image for Camunda orchestration and connectors tasks | `string` | `"camunda/camunda:8.9.0"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster to prefix resources | `string` | n/a | yes |
| <a name="input_db_admin_password"></a> [db\_admin\_password](#input\_db\_admin\_password) | Optional override for the Aurora PostgreSQL admin password. If empty, a random password is generated. | `string` | `""` | no |
| <a name="input_db_admin_username"></a> [db\_admin\_username](#input\_db\_admin\_username) | Admin username for the Aurora PostgreSQL cluster | `string` | `"camunda_admin"` | no |
| <a name="input_db_iam_auth_enabled"></a> [db\_iam\_auth\_enabled](#input\_db\_iam\_auth\_enabled) | Enable IAM database authentication on the Aurora cluster | `bool` | `true` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Database name used by Camunda components | `string` | `"camunda"` | no |
| <a name="input_db_seed_enabled"></a> [db\_seed\_enabled](#input\_db\_seed\_enabled) | Run a one-time ECS task to create/grant IAM DB users | `bool` | `true` | no |
| <a name="input_db_seed_iam_usernames"></a> [db\_seed\_iam\_usernames](#input\_db\_seed\_iam\_usernames) | Database users to create and grant rds\_iam + privileges for | `list(string)` | <pre>[<br/>  "camunda"<br/>]</pre> | no |
| <a name="input_db_seed_run_id"></a> [db\_seed\_run\_id](#input\_db\_seed\_run\_id) | Increment this value to force the DB seed task to re-run on the next apply (e.g. '1' → '2'). All SQL is idempotent so re-running is safe. | `string` | `"1"` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_enable_cross_region_dns_resolver"></a> [enable\_cross\_region\_dns\_resolver](#input\_enable\_cross\_region\_dns\_resolver) | Create Route 53 Resolver endpoints and forwarding rules for cross-region Cloud Map DNS.<br/>Requires the IAM permission route53resolver:CreateResolverEndpoint on the calling principal.<br/>Zeebe Raft and Connectors work without this because cross-region contact uses NLB DNS names.<br/>Enable once the permission is granted if you need cross-region Service Connect name resolution. | `bool` | `false` | no |
| <a name="input_limit_access_to_cidrs"></a> [limit\_access\_to\_cidrs](#input\_limit\_access\_to\_cidrs) | List of CIDR blocks to allow access to LoadBalancers | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_networking_mode"></a> [networking\_mode](#input\_networking\_mode) | Cross-region networking: 'transit\_gateway' or 'vpc\_peering' | `string` | `"transit_gateway"` | no |
| <a name="input_ports"></a> [ports](#input\_ports) | The ports to open for the security groups within the VPC | `map(number)` | <pre>{<br/>  "camunda_metrics_endpoint": 9600,<br/>  "camunda_web_ui": 8080,<br/>  "postgresql": 5432,<br/>  "zeebe_broker_network_command_api_port": 26501,<br/>  "zeebe_gateway_cluster_port": 26502,<br/>  "zeebe_gateway_network_port": 26500<br/>}</pre> | no |
| <a name="input_region_0"></a> [region\_0](#input\_region\_0) | AWS region for the primary (owner) cluster | `string` | `"eu-west-2"` | no |
| <a name="input_region_0_cidr"></a> [region\_0\_cidr](#input\_region\_0\_cidr) | VPC CIDR block for region 0 | `string` | `"10.192.0.0/16"` | no |
| <a name="input_region_1"></a> [region\_1](#input\_region\_1) | AWS region for the secondary (accepter) cluster | `string` | `"eu-west-3"` | no |
| <a name="input_region_1_cidr"></a> [region\_1\_cidr](#input\_region\_1\_cidr) | VPC CIDR block for region 1 | `string` | `"10.202.0.0/16"` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | (Optional) The password for the container registry | `string` | `""` | no |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | (Optional) The username for the container registry | `string` | `""` | no |
| <a name="input_s3_force_destroy"></a> [s3\_force\_destroy](#input\_s3\_force\_destroy) | Allow Terraform to destroy S3 backup buckets even if they contain objects | `bool` | `false` | no |
| <a name="input_secondary_storage_type"></a> [secondary\_storage\_type](#input\_secondary\_storage\_type) | Camunda secondary storage: 'rdbms' (Aurora Global) or 'opensearch' | `string` | `"rdbms"` | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Optional existing KMS key ARN for region 0. If empty, a CMK is created. | `string` | `""` | no |
| <a name="input_secrets_kms_key_arn_accepter"></a> [secrets\_kms\_key\_arn\_accepter](#input\_secrets\_kms\_key\_arn\_accepter) | Optional existing KMS key ARN for region 1. If empty, a CMK is created. | `string` | `""` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | If true, only one NAT gateway will be created per region to save on e.g. IPs, not good for HA | `bool` | `false` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admin_user_password"></a> [admin\_user\_password](#output\_admin\_user\_password) | The admin password for Camunda. Easy access purposes, saved in Secrets Manager. |
| <a name="output_aurora_global_cluster_id"></a> [aurora\_global\_cluster\_id](#output\_aurora\_global\_cluster\_id) | The ID of the Aurora Global Database cluster |
| <a name="output_aurora_primary_cluster_identifier"></a> [aurora\_primary\_cluster\_identifier](#output\_aurora\_primary\_cluster\_identifier) | The cluster identifier of the Aurora primary cluster (region 0) |
| <a name="output_aurora_primary_endpoint"></a> [aurora\_primary\_endpoint](#output\_aurora\_primary\_endpoint) | The writer endpoint of the Aurora Global DB primary cluster (region 0) |
| <a name="output_aurora_secondary_cluster_identifier"></a> [aurora\_secondary\_cluster\_identifier](#output\_aurora\_secondary\_cluster\_identifier) | The cluster identifier of the Aurora secondary cluster (region 1) |
| <a name="output_aurora_secondary_endpoint"></a> [aurora\_secondary\_endpoint](#output\_aurora\_secondary\_endpoint) | The endpoint of the Aurora Global DB secondary cluster (region 1) |
| <a name="output_opensearch_region_0_endpoint"></a> [opensearch\_region\_0\_endpoint](#output\_opensearch\_region\_0\_endpoint) | The endpoint of the OpenSearch domain in region 0 |
| <a name="output_opensearch_region_1_endpoint"></a> [opensearch\_region\_1\_endpoint](#output\_opensearch\_region\_1\_endpoint) | The endpoint of the OpenSearch domain in region 1 |
| <a name="output_region_0_alb_endpoint"></a> [region\_0\_alb\_endpoint](#output\_region\_0\_alb\_endpoint) | The DNS name of the ALB in region 0 (HTTP/REST access) |
| <a name="output_region_0_backup_bucket_name"></a> [region\_0\_backup\_bucket\_name](#output\_region\_0\_backup\_bucket\_name) | Name of the S3 backup bucket in region 0 |
| <a name="output_region_0_ecs_cluster_name"></a> [region\_0\_ecs\_cluster\_name](#output\_region\_0\_ecs\_cluster\_name) | The name of the ECS cluster in region 0 |
| <a name="output_region_0_log_group_name"></a> [region\_0\_log\_group\_name](#output\_region\_0\_log\_group\_name) | CloudWatch log group for the orchestration cluster in region 0 |
| <a name="output_region_0_nlb_grpc_endpoint"></a> [region\_0\_nlb\_grpc\_endpoint](#output\_region\_0\_nlb\_grpc\_endpoint) | The DNS name of the external NLB in region 0 (gRPC access) |
| <a name="output_region_0_nlb_raft_endpoint"></a> [region\_0\_nlb\_raft\_endpoint](#output\_region\_0\_nlb\_raft\_endpoint) | The DNS name of the internal NLB in region 0 (cross-region Raft) |
| <a name="output_region_1_alb_endpoint"></a> [region\_1\_alb\_endpoint](#output\_region\_1\_alb\_endpoint) | The DNS name of the ALB in region 1 (HTTP/REST access) |
| <a name="output_region_1_backup_bucket_name"></a> [region\_1\_backup\_bucket\_name](#output\_region\_1\_backup\_bucket\_name) | Name of the S3 backup bucket in region 1 |
| <a name="output_region_1_ecs_cluster_name"></a> [region\_1\_ecs\_cluster\_name](#output\_region\_1\_ecs\_cluster\_name) | The name of the ECS cluster in region 1 |
| <a name="output_region_1_log_group_name"></a> [region\_1\_log\_group\_name](#output\_region\_1\_log\_group\_name) | CloudWatch log group for the orchestration cluster in region 1 |
| <a name="output_region_1_nlb_grpc_endpoint"></a> [region\_1\_nlb\_grpc\_endpoint](#output\_region\_1\_nlb\_grpc\_endpoint) | The DNS name of the external NLB in region 1 (gRPC access) |
| <a name="output_region_1_nlb_raft_endpoint"></a> [region\_1\_nlb\_raft\_endpoint](#output\_region\_1\_nlb\_raft\_endpoint) | The DNS name of the internal NLB in region 1 (cross-region Raft) |
<!-- END_TF_DOCS -->
