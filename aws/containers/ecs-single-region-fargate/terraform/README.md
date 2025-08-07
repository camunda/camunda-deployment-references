# terraform

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_opensearch_domain"></a> [opensearch\_domain](#module\_opensearch\_domain) | ../../../modules/opensearch | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | v6.0.1 |
## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.core_log_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_stream.core_log_stream](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_stream) | resource |
| [aws_ecs_cluster.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_efs_access_point.camunda_data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_efs_file_system.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.efs_mounts_zone_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_efs_mount_target.efs_mounts_zone_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_efs_mount_target.efs_mounts_zone_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_iam_access_key.s3_user_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key) | resource |
| [aws_iam_policy.docker_hub_secrets_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ecs_exec_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.efs_sc_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.docker_hub_secrets_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_exec_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_efs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_user.s3_user](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user) | resource |
| [aws_iam_user_policy.s3_user_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy) | resource |
| [aws_kms_key.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_lb.grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.grpc_26500](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_8080](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.main_26500](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.main_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_s3_bucket.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_secretsmanager_secret.docker_hub_credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.docker_hub_credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.allow_necessary_camunda_ports_within_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_package_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_9090](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_service_discovery_private_dns_namespace.namespace](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_private_dns_namespace) | resource |
| [aws_service_discovery_service.discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_service) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_camunda_count"></a> [camunda\_count](#input\_camunda\_count) | The number of unique Camunda services to run | `number` | `1` | no |
| <a name="input_cidr_blocks"></a> [cidr\_blocks](#input\_cidr\_blocks) | The CIDR block to use for the VPC | `string` | `"10.200.0.0/24"` | no |
| <a name="input_docker_hub_password"></a> [docker\_hub\_password](#input\_docker\_hub\_password) | Docker Hub password or access token for authenticated pulls | `string` | `""` | no |
| <a name="input_docker_hub_username"></a> [docker\_hub\_username](#input\_docker\_hub\_username) | Docker Hub username for authenticated pulls | `string` | `""` | no |
| <a name="input_enable_alb"></a> [enable\_alb](#input\_enable\_alb) | Enable the Application Load Balancer. If false, the ALB will not be created, e.g. if a user doesn't want to publicy expose the setup. | `bool` | `true` | no |
| <a name="input_enable_nlb"></a> [enable\_nlb](#input\_enable\_nlb) | Enable the Network Load Balancer. If false, the NLB will not be created. | `bool` | `true` | no |
| <a name="input_enable_opensearch"></a> [enable\_opensearch](#input\_enable\_opensearch) | Enable the OpenSearch cluster. If false, the OpenSearch cluster will not be created. Users may want to supply DBs manually themselves. | `bool` | `false` | no |
| <a name="input_enable_opensearch_logging"></a> [enable\_opensearch\_logging](#input\_enable\_opensearch\_logging) | Enable OpenSearch logging to CloudWatch Logs | `bool` | `false` | no |
| <a name="input_enable_vpc_logging"></a> [enable\_vpc\_logging](#input\_enable\_vpc\_logging) | Enable VPC flow logging to CloudWatch Logs | `bool` | `false` | no |
| <a name="input_limit_access_to_cidrs"></a> [limit\_access\_to\_cidrs](#input\_limit\_access\_to\_cidrs) | List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_opensearch_architecture"></a> [opensearch\_architecture](#input\_opensearch\_architecture) | The architecture of the AMI to use for the OpenSearch instances. Available options: x86\_64, arm64 | `string` | `"x86_64"` | no |
| <a name="input_opensearch_dedicated_master_type"></a> [opensearch\_dedicated\_master\_type](#input\_opensearch\_dedicated\_master\_type) | The instance type to use for the dedicated OpenSearch master nodes | `map(string)` | <pre>{<br/>  "arm64": "m7g.large.search",<br/>  "x86_64": "r7g.large.search"<br/>}</pre> | no |
| <a name="input_opensearch_disk_size"></a> [opensearch\_disk\_size](#input\_opensearch\_disk\_size) | The size of the OpenSearch disk in GiB | `number` | `50` | no |
| <a name="input_opensearch_engine_version"></a> [opensearch\_engine\_version](#input\_opensearch\_engine\_version) | The engine version of the OpenSearch cluster | `string` | `"2.15"` | no |
| <a name="input_opensearch_instance_count"></a> [opensearch\_instance\_count](#input\_opensearch\_instance\_count) | The number of instances to create | `number` | `3` | no |
| <a name="input_opensearch_instance_type"></a> [opensearch\_instance\_type](#input\_opensearch\_instance\_type) | The instance type to use for the OpenSearch instances | `map(string)` | <pre>{<br/>  "arm64": "m7g.large.search",<br/>  "x86_64": "r7g.large.search"<br/>}</pre> | no |
| <a name="input_opensearch_log_types"></a> [opensearch\_log\_types](#input\_opensearch\_log\_types) | The types of logs to publish to CloudWatch Logs | `list(string)` | <pre>[<br/>  "SEARCH_SLOW_LOGS",<br/>  "INDEX_SLOW_LOGS",<br/>  "ES_APPLICATION_LOGS"<br/>]</pre> | no |
| <a name="input_ports"></a> [ports](#input\_ports) | The ports to open for the security groups within the VPC | `map(number)` | <pre>{<br/>  "camunda_metrics_endpoint": 9600,<br/>  "camunda_web_ui": 8080,<br/>  "connectors_port": 9090,<br/>  "opensearch_https": 443,<br/>  "ssh": 22,<br/>  "zeebe_broker_network_command_api_port": 26501,<br/>  "zeebe_gateway_cluster_port": 26502,<br/>  "zeebe_gateway_network_port": 26500<br/>}</pre> | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for names of resources | `string` | `"lars-ecs-v2"` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_endpoint"></a> [alb\_endpoint](#output\_alb\_endpoint) | (Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp. |
| <a name="output_aws_opensearch_domain"></a> [aws\_opensearch\_domain](#output\_aws\_opensearch\_domain) | (Optional) The endpoint of the OpenSearch domain. |
| <a name="output_nlb_endpoint"></a> [nlb\_endpoint](#output\_nlb\_endpoint) | (Optional) The DNS name of the Network Load Balancer (NLB) to access the Camunda Core. |
| <a name="output_s3_access_key_id"></a> [s3\_access\_key\_id](#output\_s3\_access\_key\_id) | The access key ID for S3 bucket access |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | The ARN of the S3 bucket |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | The name of the S3 bucket |
| <a name="output_s3_secret_access_key"></a> [s3\_secret\_access\_key](#output\_s3\_secret\_access\_key) | The secret access key for S3 bucket access |
<!-- END_TF_DOCS -->
