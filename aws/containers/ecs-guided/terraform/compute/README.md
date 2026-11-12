# Compute stage

The ECS cluster and what every service shares: task execution role, security groups, registry credentials and the KMS key for secrets. Stages that create secrets attach a read policy to `task_execution_role_name`.

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.components](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_iam_policy.registry_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.registry_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_secretsmanager_secret.registry_credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.registry_credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.camunda_ports_within_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.egress_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_service_discovery_http_namespace.service_connect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_http_namespace) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_cidr_blocks"></a> [additional\_cidr\_blocks](#input\_additional\_cidr\_blocks) | CIDR blocks of other VPCs, for example the second region, allowed on the same Camunda ports. Empty for a single region. | `list(string)` | `[]` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_enable_management_plane"></a> [enable\_management\_plane](#input\_enable\_management\_plane) | Open the ports of the management plane components in the shared security group. Set it in the compute stage that hosts the OIDC provider, Management Identity, and Camunda Hub. | `bool` | `false` | no |
| <a name="input_management_plane_ports"></a> [management\_plane\_ports](#input\_management\_plane\_ports) | Ports of the management plane components (OIDC provider, Management Identity, Camunda Hub), opened inside the VPC when enable\_management\_plane is true | `map(number)` | <pre>{<br/>  "camunda_hub_management": 8091,<br/>  "camunda_hub_restapi": 8081,<br/>  "camunda_hub_websockets": 8060,<br/>  "management_identity_app": 8084,<br/>  "management_identity_management": 8082,<br/>  "oidc_provider_http": 18080,<br/>  "oidc_provider_management": 9000<br/>}</pre> | no |
| <a name="input_ports"></a> [ports](#input\_ports) | Ports opened between the tasks and the database inside the VPC | `map(number)` | <pre>{<br/>  "camunda_metrics_endpoint": 9600,<br/>  "camunda_web_ui": 8080,<br/>  "postgresql": 5432,<br/>  "zeebe_broker_network_command_api_port": 26501,<br/>  "zeebe_gateway_cluster_port": 26502,<br/>  "zeebe_gateway_network_port": 26500<br/>}</pre> | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | Password for a private image registry | `string` | `""` | no |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | Username for a private image registry. Leave empty when the images are public. | `string` | `""` | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Existing KMS key to encrypt Secrets Manager secrets with. When empty, this stage creates one and every later stage uses it. | `string` | `""` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | Network stage output: CIDR block of the VPC, used for the intra-VPC security group rules | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Network stage output: ID of the VPC | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_camunda_ports_security_group_id"></a> [camunda\_ports\_security\_group\_id](#output\_camunda\_ports\_security\_group\_id) | Security group that opens the Camunda ports inside the VPC. Attach it to every service and to the load balancers. |
| <a name="output_components_log_group_name"></a> [components\_log\_group\_name](#output\_components\_log\_group\_name) | CloudWatch log group for the components that run outside an Orchestration Cluster |
| <a name="output_ecs_cluster_arn"></a> [ecs\_cluster\_arn](#output\_ecs\_cluster\_arn) | ARN of the ECS cluster |
| <a name="output_ecs_cluster_id"></a> [ecs\_cluster\_id](#output\_ecs\_cluster\_id) | ID of the ECS cluster |
| <a name="output_efs_security_group_id"></a> [efs\_security\_group\_id](#output\_efs\_security\_group\_id) | Security group of the EFS file systems |
| <a name="output_egress_security_group_id"></a> [egress\_security\_group\_id](#output\_egress\_security\_group\_id) | Security group that allows outbound HTTP and HTTPS |
| <a name="output_registry_credentials_arn"></a> [registry\_credentials\_arn](#output\_registry\_credentials\_arn) | ARN of the registry credentials secret, empty when no registry credentials are configured |
| <a name="output_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#output\_secrets\_kms\_key\_arn) | KMS key that encrypts the Secrets Manager secrets of every stage |
| <a name="output_service_connect_namespace_arn"></a> [service\_connect\_namespace\_arn](#output\_service\_connect\_namespace\_arn) | Service Connect namespace for the components that run outside an Orchestration Cluster |
| <a name="output_task_execution_role_arn"></a> [task\_execution\_role\_arn](#output\_task\_execution\_role\_arn) | ARN of the ECS task execution role |
| <a name="output_task_execution_role_name"></a> [task\_execution\_role\_name](#output\_task\_execution\_role\_name) | Name of the ECS task execution role. Stages that create secrets attach a read policy to it. |
<!-- END_TF_DOCS -->
