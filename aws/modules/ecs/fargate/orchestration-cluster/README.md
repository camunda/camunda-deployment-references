# orchestration-cluster

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.orchestration_cluster_log_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_stream.orchestration_cluster_log_stream](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_stream) | resource |
| [aws_ecs_service.orchestration_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.orchestration_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_efs_access_point.camunda_data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_efs_file_system.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.efs_mounts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_iam_policy.ecs_exec_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.efs_sc_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ecs_exec_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_efs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_s3_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_role_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_lb_listener.grpc_26500](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.main_26500](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.main_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_s3_bucket.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_service_discovery_http_namespace.service_connect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_http_namespace) | resource |
| [aws_service_discovery_private_dns_namespace.namespace](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_private_dns_namespace) | resource |
| [aws_service_discovery_service.discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_service) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_arn"></a> [alb\_arn](#input\_alb\_arn) | The ARN of the Application Load Balancer to use | `string` | `""` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | The AWS region to deploy resources in | `string` | n/a | yes |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | The cluster id of the ECS cluster to spawn the ECS service in | `string` | n/a | yes |
| <a name="input_efs_security_group_ids"></a> [efs\_security\_group\_ids](#input\_efs\_security\_group\_ids) | List of security group IDs to associate with the EFS file system | `list(string)` | `[]` | no |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | List of environment variable name-value pairs to set in the ECS task | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_task_role_attachments"></a> [extra\_task\_role\_attachments](#input\_extra\_task\_role\_attachments) | List of additional IAM policy ARNs to attach to the ECS task role | `list(string)` | `[]` | no |
| <a name="input_image"></a> [image](#input\_image) | The container image to use for the Camunda orchestration cluster | `string` | `"camunda/camunda:SNAPSHOT"` | no |
| <a name="input_nlb_arn"></a> [nlb\_arn](#input\_nlb\_arn) | The ARN of the Network Load Balancer to use | `string` | `""` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for naming resources | `string` | n/a | yes |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | The ARN of the Secrets Manager secret containing registry credentials | `string` | `""` | no |
| <a name="input_service_force_new_deployment"></a> [service\_force\_new\_deployment](#input\_service\_force\_new\_deployment) | Whether to force a new deployment of the ECS service | `bool` | `false` | no |
| <a name="input_service_security_group_ids"></a> [service\_security\_group\_ids](#input\_service\_security\_group\_ids) | List of security group IDs to associate with the ECS service | `list(string)` | `[]` | no |
| <a name="input_task_cpu"></a> [task\_cpu](#input\_task\_cpu) | The amount of cpu to allocate to the ECS task | `number` | `4096` | no |
| <a name="input_task_desired_count"></a> [task\_desired\_count](#input\_task\_desired\_count) | The desired count of ECS tasks to run in the ECS service - directly impacts the Zeebe cluster size | `number` | `3` | no |
| <a name="input_task_enable_execute_command"></a> [task\_enable\_execute\_command](#input\_task\_enable\_execute\_command) | Whether to enable execute command for the ECS service | `bool` | `true` | no |
| <a name="input_task_memory"></a> [task\_memory](#input\_task\_memory) | The amount of memory to allocate to the ECS task | `number` | `8192` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC id where the ECS cluster and service are deployed | `string` | n/a | yes |
| <a name="input_vpc_private_subnets"></a> [vpc\_private\_subnets](#input\_vpc\_private\_subnets) | List of private subnet IDs within the VPC | `list(string)` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | The name of the S3 bucket |
<!-- END_TF_DOCS -->
