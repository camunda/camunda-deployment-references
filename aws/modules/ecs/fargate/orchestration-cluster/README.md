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
| [aws_iam_policy.orchestration_cluster_logs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecs_exec_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_efs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_s3_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.orchestration_cluster_logs_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_role_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_lb_listener.grpc_26500](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.http_management](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.http_webapp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
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
| <a name="input_alb_listener_http_management_arn"></a> [alb\_listener\_http\_management\_arn](#input\_alb\_listener\_http\_management\_arn) | The ARN of the ALB listener for the management port HTTP(s) traffic | `string` | `""` | no |
| <a name="input_alb_listener_http_webapp_arn"></a> [alb\_listener\_http\_webapp\_arn](#input\_alb\_listener\_http\_webapp\_arn) | The ARN of the ALB listener for the web application port HTTP(s) traffic | `string` | `""` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | The AWS region to deploy resources in | `string` | n/a | yes |
| <a name="input_cloudwatch_retention_days"></a> [cloudwatch\_retention\_days](#input\_cloudwatch\_retention\_days) | The number of days to retain CloudWatch logs | `number` | `30` | no |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | The cluster id of the ECS cluster to spawn the ECS service in | `string` | n/a | yes |
| <a name="input_ecs_task_execution_role_arn"></a> [ecs\_task\_execution\_role\_arn](#input\_ecs\_task\_execution\_role\_arn) | ARN of the ECS task execution role (centrally managed) | `string` | n/a | yes |
| <a name="input_efs_performance_mode"></a> [efs\_performance\_mode](#input\_efs\_performance\_mode) | The performance mode for the EFS file system | `string` | `"generalPurpose"` | no |
| <a name="input_efs_provisioned_throughput_in_mibps"></a> [efs\_provisioned\_throughput\_in\_mibps](#input\_efs\_provisioned\_throughput\_in\_mibps) | The provisioned throughput in MiB/s for the EFS file system if using provisioned mode | `number` | `50` | no |
| <a name="input_efs_security_group_ids"></a> [efs\_security\_group\_ids](#input\_efs\_security\_group\_ids) | List of security group IDs to associate with the EFS file system | `list(string)` | `[]` | no |
| <a name="input_efs_throughput_mode"></a> [efs\_throughput\_mode](#input\_efs\_throughput\_mode) | The throughput mode for the EFS file system | `string` | `"provisioned"` | no |
| <a name="input_enable_alb_http_management_listener_rule"></a> [enable\_alb\_http\_management\_listener\_rule](#input\_enable\_alb\_http\_management\_listener\_rule) | Whether to create the ALB listener rule for the management port (must be a known boolean at plan time) | `bool` | `false` | no |
| <a name="input_enable_alb_http_webapp_listener_rule"></a> [enable\_alb\_http\_webapp\_listener\_rule](#input\_enable\_alb\_http\_webapp\_listener\_rule) | Whether to create the ALB listener rule for the WebApp (must be a known boolean at plan time) | `bool` | `true` | no |
| <a name="input_enable_nlb_grpc_26500_listener"></a> [enable\_nlb\_grpc\_26500\_listener](#input\_enable\_nlb\_grpc\_26500\_listener) | Whether to create the NLB listener on port 26500 (must be a known boolean at plan time) | `bool` | `true` | no |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | List of environment variable name-value pairs to set in the ECS task | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_task_role_attachments"></a> [extra\_task\_role\_attachments](#input\_extra\_task\_role\_attachments) | List of additional IAM policy ARNs to attach to the ECS task role | `list(string)` | `[]` | no |
| <a name="input_image"></a> [image](#input\_image) | The container image to use for the Camunda orchestration cluster | `string` | `"camunda/camunda:8.9.0-alpha4"` | no |
| <a name="input_init_container_command"></a> [init\_container\_command](#input\_init\_container\_command) | Command for the init container (Docker CMD). If empty, uses the image default. | `list(string)` | `[]` | no |
| <a name="input_init_container_enabled"></a> [init\_container\_enabled](#input\_init\_container\_enabled) | Whether to add an init container that must complete successfully before the main container starts. | `bool` | `false` | no |
| <a name="input_init_container_environment_variables"></a> [init\_container\_environment\_variables](#input\_init\_container\_environment\_variables) | Environment variables for the init container. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_init_container_image"></a> [init\_container\_image](#input\_init\_container\_image) | Container image for the init container. | `string` | `""` | no |
| <a name="input_init_container_name"></a> [init\_container\_name](#input\_init\_container\_name) | Name of the init container (referenced by dependsOn). | `string` | `"init"` | no |
| <a name="input_init_container_secrets"></a> [init\_container\_secrets](#input\_init\_container\_secrets) | ECS task secrets for the init container (rendered as container definition 'secrets'). | <pre>list(object({<br/>    name      = string<br/>    valueFrom = string<br/>  }))</pre> | `[]` | no |
| <a name="input_nlb_arn"></a> [nlb\_arn](#input\_nlb\_arn) | The ARN of the Network Load Balancer to use | `string` | `""` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for naming resources | `string` | n/a | yes |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | The ARN of the Secrets Manager secret containing registry credentials | `string` | `""` | no |
| <a name="input_restore_backup_id"></a> [restore\_backup\_id](#input\_restore\_backup\_id) | The backup ID to restore from. When set, enables the restore init container that runs before the main container. | `string` | `""` | no |
| <a name="input_restore_container_entrypoint"></a> [restore\_container\_entrypoint](#input\_restore\_container\_entrypoint) | Entrypoint for the restore init container (Docker ENTRYPOINT). Defaults to the restore application. | `list(string)` | <pre>[<br/>  "bash",<br/>  "-c",<br/>  "/usr/local/camunda/bin/restore --backupId=$BACKUP_ID"<br/>]</pre> | no |
| <a name="input_restore_container_image"></a> [restore\_container\_image](#input\_restore\_container\_image) | Container image for the restore init container. Required when restore\_backup\_id is set. | `string` | `"camunda/camunda:8.9.0-alpha4"` | no |
| <a name="input_restore_container_secrets"></a> [restore\_container\_secrets](#input\_restore\_container\_secrets) | ECS task secrets for the restore init container (rendered as container definition 'secrets'). | <pre>list(object({<br/>    name      = string<br/>    valueFrom = string<br/>  }))</pre> | `[]` | no |
| <a name="input_s3_force_destroy"></a> [s3\_force\_destroy](#input\_s3\_force\_destroy) | Whether to force destroy the S3 bucket even if it contains objects. Set to true for dev/test environments. | `bool` | `false` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | List of ECS task secrets to expose to the container (rendered as container definition 'secrets'). Each item must be { name = string, valueFrom = string } where valueFrom is typically a Secrets Manager secret ARN. | <pre>list(object({<br/>    name      = string<br/>    valueFrom = string<br/>  }))</pre> | `[]` | no |
| <a name="input_service_force_new_deployment"></a> [service\_force\_new\_deployment](#input\_service\_force\_new\_deployment) | Whether to force a new deployment of the ECS service | `bool` | `false` | no |
| <a name="input_service_health_check_grace_period_seconds"></a> [service\_health\_check\_grace\_period\_seconds](#input\_service\_health\_check\_grace\_period\_seconds) | Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown | `number` | `900` | no |
| <a name="input_service_security_group_ids"></a> [service\_security\_group\_ids](#input\_service\_security\_group\_ids) | List of security group IDs to associate with the ECS service | `list(string)` | `[]` | no |
| <a name="input_service_timeouts"></a> [service\_timeouts](#input\_service\_timeouts) | Timeout configuration for ECS service operations | <pre>object({<br/>    create = optional(string, "30m")<br/>    update = optional(string, "30m")<br/>    delete = optional(string, "20m")<br/>  })</pre> | <pre>{<br/>  "create": "30m",<br/>  "delete": "20m",<br/>  "update": "30m"<br/>}</pre> | no |
| <a name="input_task_cpu"></a> [task\_cpu](#input\_task\_cpu) | The amount of cpu to allocate to the ECS task | `number` | `4096` | no |
| <a name="input_task_cpu_architecture"></a> [task\_cpu\_architecture](#input\_task\_cpu\_architecture) | The CPU architecture to use for the ECS task | `string` | `"X86_64"` | no |
| <a name="input_task_desired_count"></a> [task\_desired\_count](#input\_task\_desired\_count) | The desired count of ECS tasks to run in the ECS service - directly impacts the Zeebe cluster size | `number` | `3` | no |
| <a name="input_task_enable_execute_command"></a> [task\_enable\_execute\_command](#input\_task\_enable\_execute\_command) | Whether to enable execute command for the ECS service | `bool` | `false` | no |
| <a name="input_task_memory"></a> [task\_memory](#input\_task\_memory) | The amount of memory to allocate to the ECS task | `number` | `8192` | no |
| <a name="input_task_operating_system_family"></a> [task\_operating\_system\_family](#input\_task\_operating\_system\_family) | The operating system family to use for the ECS task | `string` | `"LINUX"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC id where the ECS cluster and service are deployed | `string` | n/a | yes |
| <a name="input_vpc_private_subnets"></a> [vpc\_private\_subnets](#input\_vpc\_private\_subnets) | List of private subnet IDs within the VPC | `list(string)` | n/a | yes |
| <a name="input_wait_for_steady_state"></a> [wait\_for\_steady\_state](#input\_wait\_for\_steady\_state) | Whether to wait for the ECS service to reach a steady state after deployment | `bool` | `true` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_a_record"></a> [dns\_a\_record](#output\_dns\_a\_record) | n/a |
| <a name="output_grpc_service_connect"></a> [grpc\_service\_connect](#output\_grpc\_service\_connect) | The Service Connect discovery name for the orchestration cluster ECS service targeting gRPC |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | The name of the CloudWatch log group for the orchestration cluster |
| <a name="output_rest_service_connect"></a> [rest\_service\_connect](#output\_rest\_service\_connect) | The Service Connect discovery name for the orchestration cluster ECS service targeting REST |
| <a name="output_s2s_cloudmap_namespace"></a> [s2s\_cloudmap\_namespace](#output\_s2s\_cloudmap\_namespace) | The ARN of the Service Connect namespace for service-to-service communication |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | The name of the S3 bucket |
<!-- END_TF_DOCS -->
