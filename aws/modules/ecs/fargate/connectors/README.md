# connectors

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_ecs_service.connectors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.connectors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.ecs_exec_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ecs_exec_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.service_role_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_role_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lb_listener_rule.http_80](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_arn"></a> [alb\_arn](#input\_alb\_arn) | The ARN of the Application Load Balancer to use | `string` | `""` | no |
| <a name="input_alb_listener_http_80_arn"></a> [alb\_listener\_http\_80\_arn](#input\_alb\_listener\_http\_80\_arn) | The ARN of the ALB listener for HTTP on port 80 | `string` | `""` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | The AWS region to deploy resources in | `string` | n/a | yes |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | The cluster id of the ECS cluster to spawn the ECS service in | `string` | n/a | yes |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | List of environment variable name-value pairs to set in the ECS task | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_service_role_attachments"></a> [extra\_service\_role\_attachments](#input\_extra\_service\_role\_attachments) | List of additional IAM policy ARNs to attach to the ECS service role | `list(string)` | `[]` | no |
| <a name="input_extra_task_role_attachments"></a> [extra\_task\_role\_attachments](#input\_extra\_task\_role\_attachments) | List of additional IAM policy ARNs to attach to the ECS task role | `list(string)` | `[]` | no |
| <a name="input_image"></a> [image](#input\_image) | The container image to use for the Camunda orchestration cluster | `string` | `"camunda/connectors-bundle:SNAPSHOT"` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | The name of the CloudWatch log group for the ECS tasks | `string` | `""` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for naming resources | `string` | n/a | yes |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | The ARN of the Secrets Manager secret containing registry credentials | `string` | `""` | no |
| <a name="input_s2s_cloudmap_namespace"></a> [s2s\_cloudmap\_namespace](#input\_s2s\_cloudmap\_namespace) | The ARN of the Service Connect namespace for service-to-service communication | `string` | `""` | no |
| <a name="input_service_force_new_deployment"></a> [service\_force\_new\_deployment](#input\_service\_force\_new\_deployment) | Whether to force a new deployment of the ECS service | `bool` | `false` | no |
| <a name="input_service_security_group_ids"></a> [service\_security\_group\_ids](#input\_service\_security\_group\_ids) | List of security group IDs to associate with the ECS service | `list(string)` | `[]` | no |
| <a name="input_service_timeouts"></a> [service\_timeouts](#input\_service\_timeouts) | Timeout configuration for ECS service operations | <pre>object({<br/>    create = optional(string, "30m")<br/>    update = optional(string, "30m")<br/>    delete = optional(string, "20m")<br/>  })</pre> | <pre>{<br/>  "create": "30m",<br/>  "delete": "20m",<br/>  "update": "30m"<br/>}</pre> | no |
| <a name="input_task_cpu"></a> [task\_cpu](#input\_task\_cpu) | The amount of cpu to allocate to the ECS task | `number` | `1024` | no |
| <a name="input_task_desired_count"></a> [task\_desired\_count](#input\_task\_desired\_count) | The desired count of ECS tasks to run in the ECS service - directly impacts the Zeebe cluster size | `number` | `1` | no |
| <a name="input_task_enable_execute_command"></a> [task\_enable\_execute\_command](#input\_task\_enable\_execute\_command) | Whether to enable execute command for the ECS service | `bool` | `true` | no |
| <a name="input_task_memory"></a> [task\_memory](#input\_task\_memory) | The amount of memory to allocate to the ECS task | `number` | `2048` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC id where the ECS cluster and service are deployed | `string` | n/a | yes |
| <a name="input_vpc_private_subnets"></a> [vpc\_private\_subnets](#input\_vpc\_private\_subnets) | List of private subnet IDs within the VPC | `list(string)` | n/a | yes |
| <a name="input_wait_for_steady_state"></a> [wait\_for\_steady\_state](#input\_wait\_for\_steady\_state) | Whether to wait for the ECS service to reach a steady state after deployment | `bool` | `true` | no |
## Outputs

No outputs.
<!-- END_TF_DOCS -->
