# connectors

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_ecs_service.connectors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.connectors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.connectors_logs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ecs_exec_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.connectors_logs_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_exec_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_role_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lb_listener_rule.http_webapp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_arn"></a> [alb\_arn](#input\_alb\_arn) | The ARN of the Application Load Balancer to use | `string` | `""` | no |
| <a name="input_alb_listener_http_webapp_arn"></a> [alb\_listener\_http\_webapp\_arn](#input\_alb\_listener\_http\_webapp\_arn) | The ARN of the ALB listener for the web application port HTTP(s) traffic | `string` | `""` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | The AWS region to deploy resources in | `string` | n/a | yes |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | The cluster id of the ECS cluster to spawn the ECS service in | `string` | n/a | yes |
| <a name="input_ecs_task_execution_role_arn"></a> [ecs\_task\_execution\_role\_arn](#input\_ecs\_task\_execution\_role\_arn) | ARN of the ECS task execution role (centrally managed) | `string` | n/a | yes |
| <a name="input_enable_alb_http_webapp_listener_rule"></a> [enable\_alb\_http\_webapp\_listener\_rule](#input\_enable\_alb\_http\_webapp\_listener\_rule) | Whether to create the ALB listener rule for the WebApp (must be a known boolean at plan time) | `bool` | `true` | no |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | List of environment variable name-value pairs to set in the ECS task | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_task_role_attachments"></a> [extra\_task\_role\_attachments](#input\_extra\_task\_role\_attachments) | List of additional IAM policy ARNs to attach to the ECS task role | `list(string)` | `[]` | no |
| <a name="input_image"></a> [image](#input\_image) | The container image to use for the Camunda Connectors | `string` | `"camunda/connectors-bundle:8.9.0-alpha3"` | no |
| <a name="input_init_container_command"></a> [init\_container\_command](#input\_init\_container\_command) | Command for the init container (Docker CMD). If empty, uses the image default. | `list(string)` | `[]` | no |
| <a name="input_init_container_enabled"></a> [init\_container\_enabled](#input\_init\_container\_enabled) | Whether to add an init container that must complete successfully before the main container starts. | `bool` | `false` | no |
| <a name="input_init_container_environment_variables"></a> [init\_container\_environment\_variables](#input\_init\_container\_environment\_variables) | Environment variables for the init container. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_init_container_image"></a> [init\_container\_image](#input\_init\_container\_image) | Container image for the init container. | `string` | `""` | no |
| <a name="input_init_container_name"></a> [init\_container\_name](#input\_init\_container\_name) | Name of the init container (referenced by dependsOn). | `string` | `"init"` | no |
| <a name="input_init_container_secrets"></a> [init\_container\_secrets](#input\_init\_container\_secrets) | ECS task secrets for the init container (rendered as container definition 'secrets'). | <pre>list(object({<br/>    name      = string<br/>    valueFrom = string<br/>  }))</pre> | `[]` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | The name of the CloudWatch log group for the ECS tasks | `string` | `""` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for naming resources | `string` | n/a | yes |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | The ARN of the Secrets Manager secret containing registry credentials | `string` | `""` | no |
| <a name="input_s2s_cloudmap_namespace"></a> [s2s\_cloudmap\_namespace](#input\_s2s\_cloudmap\_namespace) | The ARN of the Service Connect namespace for service-to-service communication | `string` | `""` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | List of ECS task secrets to expose to the container (rendered as container definition 'secrets'). Each item must be { name = string, valueFrom = string } where valueFrom is typically a Secrets Manager secret ARN. | <pre>list(object({<br/>    name      = string<br/>    valueFrom = string<br/>  }))</pre> | `[]` | no |
| <a name="input_service_force_new_deployment"></a> [service\_force\_new\_deployment](#input\_service\_force\_new\_deployment) | Whether to force a new deployment of the ECS service | `bool` | `false` | no |
| <a name="input_service_health_check_grace_period_seconds"></a> [service\_health\_check\_grace\_period\_seconds](#input\_service\_health\_check\_grace\_period\_seconds) | Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown | `number` | `300` | no |
| <a name="input_service_security_group_ids"></a> [service\_security\_group\_ids](#input\_service\_security\_group\_ids) | List of security group IDs to associate with the ECS service | `list(string)` | `[]` | no |
| <a name="input_service_timeouts"></a> [service\_timeouts](#input\_service\_timeouts) | Timeout configuration for ECS service operations | <pre>object({<br/>    create = optional(string, "30m")<br/>    update = optional(string, "30m")<br/>    delete = optional(string, "20m")<br/>  })</pre> | <pre>{<br/>  "create": "30m",<br/>  "delete": "20m",<br/>  "update": "30m"<br/>}</pre> | no |
| <a name="input_task_cpu"></a> [task\_cpu](#input\_task\_cpu) | The amount of cpu to allocate to the ECS task | `number` | `2048` | no |
| <a name="input_task_cpu_architecture"></a> [task\_cpu\_architecture](#input\_task\_cpu\_architecture) | The CPU architecture to use for the ECS task | `string` | `"X86_64"` | no |
| <a name="input_task_desired_count"></a> [task\_desired\_count](#input\_task\_desired\_count) | The desired count of ECS tasks to run in the ECS service - directly impacts the Zeebe cluster size | `number` | `1` | no |
| <a name="input_task_enable_execute_command"></a> [task\_enable\_execute\_command](#input\_task\_enable\_execute\_command) | Whether to enable execute command for the ECS service | `bool` | `false` | no |
| <a name="input_task_memory"></a> [task\_memory](#input\_task\_memory) | The amount of memory to allocate to the ECS task | `number` | `4096` | no |
| <a name="input_task_operating_system_family"></a> [task\_operating\_system\_family](#input\_task\_operating\_system\_family) | The operating system family to use for the ECS task | `string` | `"LINUX"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC id where the ECS cluster and service are deployed | `string` | n/a | yes |
| <a name="input_vpc_private_subnets"></a> [vpc\_private\_subnets](#input\_vpc\_private\_subnets) | List of private subnet IDs within the VPC | `list(string)` | n/a | yes |
| <a name="input_wait_for_steady_state"></a> [wait\_for\_steady\_state](#input\_wait\_for\_steady\_state) | Whether to wait for the ECS service to reach a steady state after deployment | `bool` | `true` | no |
## Outputs

No outputs.
<!-- END_TF_DOCS -->
