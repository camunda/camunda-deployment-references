# load-generator

Drives a steady rate of process instances at an Orchestration Cluster running
on ECS Fargate, so the cluster can be observed under load rather than at rest.

Every other check in a reference architecture samples the cluster at a point in
time. A generator writing continuously is what makes a throughput dip during a
broker restart or a failover visible at all, which is why this pairs naturally
with the [monitoring](../monitoring/README.md) module and the
[FIS chaos experiments](../../../../common/procedure/chaos-fis/README.md).

Absorbed from [`camunda/camunda-load-tests-ecs`](https://github.com/camunda/camunda-load-tests-ecs)
per [team-infrastructure-experience#464](https://github.com/camunda/team-infrastructure-experience/issues/464).

## Usage

```hcl
module "load_generator" {
  source = "../../../../modules/ecs/fargate/load-generator"

  prefix              = "camunda-lt"
  ecs_cluster_id      = aws_ecs_cluster.ecs.id
  vpc_id              = module.vpc.vpc_id
  vpc_private_subnets = module.vpc.private_subnets
  aws_region          = data.aws_region.current.region

  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  camunda_host             = module.orchestration_cluster.dns_a_record
  auth_username            = "admin"
  auth_password_secret_arn = aws_secretsmanager_secret.admin_user_password.arn

  start_rate = 10
}
```

The execution role must be allowed to read `auth_password_secret_arn`; the
password reaches the container as an ECS secret, never as a plain environment
variable.

Total throughput is `start_rate * task_desired_count`. Setting
`task_desired_count = 0` parks the generator without destroying it, which is
the cheapest way to stop load between runs.

Watch it work through its CloudWatch log group:

```bash
aws logs tail "$(terraform output -raw load_generator_log_group)" --follow
```

## Why the community benchmark, and not the reliability-testing images

The absorbed repository ran `registry.camunda.cloud/team-zeebe/starter` and
`/worker`. Those are not publicly pullable, and everything in this repository
exists to be copied by people outside Camunda, so an image they cannot pull is
disqualifying. This module runs
[`camunda-8-benchmark`](https://github.com/camunda-community-hub/camunda-8-benchmark)
instead, which is public and is also what customers run, so exercising it here
is coverage of the path they are on.

The same reasoning, at more length, is in
[`aws/kubernetes/eks-multi-region-rdbms/DEVELOPER.md`](../../../../kubernetes/eks-multi-region-rdbms/DEVELOPER.md).
Consolidation of the two load-testing stacks is tracked in
[camunda/camunda#51191](https://github.com/camunda/camunda/issues/51191); revisit
this choice when that lands.

## Defaults worth knowing

**The rate is fixed, not adaptive.** `rate_adjustment_strategy` defaults to
`none` because a strategy that backs off when the cluster slows down hides
exactly the dip a resilience test exists to show.

**Workers run alongside the starter.** Without them, started instances pile up
as active work and the export rate stops tracking the start rate, which is the
number the generator is there to hold steady.

**`multiple_job_types` must match the process.** The benchmark derives job types
by suffixing `job_type` with `1..N`. A service task whose type nothing
subscribes to leaves every instance stuck on it.

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.load_generator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_service.load_generator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.load_generator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.ecs_exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecs_exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_auth_method"></a> [auth\_method](#input\_auth\_method) | How the generator authenticates against the Orchestration Cluster. The ECS reference deploys no Management Identity, so it runs basic auth. | `string` | `"basic"` | no |
| <a name="input_auth_password_secret_arn"></a> [auth\_password\_secret\_arn](#input\_auth\_password\_secret\_arn) | ARN of the Secrets Manager secret holding the password. Required when auth\_method is basic. Passed as an ECS secret so it never appears in the task definition. | `string` | `""` | no |
| <a name="input_auth_username"></a> [auth\_username](#input\_auth\_username) | Username used when auth\_method is basic | `string` | `"demo"` | no |
| <a name="input_auto_deploy_process"></a> [auto\_deploy\_process](#input\_auto\_deploy\_process) | Whether the generator deploys its process definition on startup. | `bool` | `true` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | The AWS region to deploy resources in | `string` | n/a | yes |
| <a name="input_bpmn_process_id"></a> [bpmn\_process\_id](#input\_bpmn\_process\_id) | Process id to start. Leave empty to use the image's built-in benchmark process. | `string` | `""` | no |
| <a name="input_bpmn_resource"></a> [bpmn\_resource](#input\_bpmn\_resource) | Location of the process definition to deploy, for example 'classpath:bpmn/one\_task.bpmn'. Leave empty to use the image default; ECS has no ConfigMap equivalent, so a custom file needs a volume you mount yourself. | `string` | `""` | no |
| <a name="input_camunda_grpc_port"></a> [camunda\_grpc\_port](#input\_camunda\_grpc\_port) | The gRPC port of the Orchestration Cluster gateway | `number` | `26500` | no |
| <a name="input_camunda_host"></a> [camunda\_host](#input\_camunda\_host) | Hostname of the Orchestration Cluster to drive load against, typically the Cloud Map record of the orchestration-cluster module (orchestration-cluster.<prefix>.service.local). | `string` | n/a | yes |
| <a name="input_camunda_rest_port"></a> [camunda\_rest\_port](#input\_camunda\_rest\_port) | The REST port of the Orchestration Cluster gateway | `number` | `8080` | no |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | The cluster id of the ECS cluster to spawn the ECS service in | `string` | n/a | yes |
| <a name="input_ecs_task_execution_role_arn"></a> [ecs\_task\_execution\_role\_arn](#input\_ecs\_task\_execution\_role\_arn) | ARN of the ECS task execution role (centrally managed). It must be allowed to read auth\_password\_secret\_arn. | `string` | n/a | yes |
| <a name="input_extra_environment_variables"></a> [extra\_environment\_variables](#input\_extra\_environment\_variables) | Additional environment variables appended to the container definition, for benchmark settings this module does not surface. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_image"></a> [image](#input\_image) | The container image used to generate load. Defaults to the community benchmark project, which is publicly pullable; the Camunda reliability-testing images are not. | `string` | `"camundacommunityhub/camunda-8-benchmark:main"` | no |
| <a name="input_job_type"></a> [job\_type](#input\_job\_type) | The job type the workers subscribe to. Must match the service tasks in the deployed process. | `string` | `"benchmark-task"` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | The name of an existing CloudWatch log group for the ECS tasks. When empty, the module creates its own log group. | `string` | `""` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Root log level of the generator. The throughput lines it prints are INFO. | `string` | `"INFO"` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | Retention of the CloudWatch log group created by this module. Ignored when log\_group\_name is supplied. | `number` | `7` | no |
| <a name="input_multiple_job_types"></a> [multiple\_job\_types](#input\_multiple\_job\_types) | Number of job types, derived by suffixing job\_type with 1..N. Must equal the number of service tasks in the process, or instances get stuck on a task nothing subscribes to. | `number` | `1` | no |
| <a name="input_prefer_rest_over_grpc"></a> [prefer\_rest\_over\_grpc](#input\_prefer\_rest\_over\_grpc) | Whether the client should prefer the REST API over gRPC | `bool` | `false` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for naming resources | `string` | n/a | yes |
| <a name="input_rate_adjustment_strategy"></a> [rate\_adjustment\_strategy](#input\_rate\_adjustment\_strategy) | How the generator reacts when the cluster slows down. 'none' holds a fixed rate, which is what makes a throughput dip visible instead of absorbed. | `string` | `"none"` | no |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | The ARN of the Secrets Manager secret containing registry credentials, when the image is pulled from a private registry. Not needed for the default public image. | `string` | `""` | no |
| <a name="input_service_force_new_deployment"></a> [service\_force\_new\_deployment](#input\_service\_force\_new\_deployment) | Whether to force a new deployment of the ECS service. Set it to restart the generator without changing its configuration. | `bool` | `false` | no |
| <a name="input_service_security_group_ids"></a> [service\_security\_group\_ids](#input\_service\_security\_group\_ids) | List of security group IDs to associate with the ECS service | `list(string)` | `[]` | no |
| <a name="input_service_timeouts"></a> [service\_timeouts](#input\_service\_timeouts) | Timeout configuration for ECS service operations | <pre>object({<br/>    create = optional(string, "15m")<br/>    update = optional(string, "30m")<br/>    delete = optional(string, "20m")<br/>  })</pre> | <pre>{<br/>  "create": "15m",<br/>  "delete": "20m",<br/>  "update": "30m"<br/>}</pre> | no |
| <a name="input_start_rate"></a> [start\_rate](#input\_start\_rate) | Process instances started per second, per task. | `number` | `10` | no |
| <a name="input_start_workers"></a> [start\_workers](#input\_start\_workers) | Whether to run job workers alongside the starter. Without them instances pile up as active work and the export rate stops tracking the start rate. | `bool` | `true` | no |
| <a name="input_task_completion_delay"></a> [task\_completion\_delay](#input\_task\_completion\_delay) | Milliseconds a worker waits before completing a job, standing in for real work. | `number` | `50` | no |
| <a name="input_task_cpu"></a> [task\_cpu](#input\_task\_cpu) | The amount of cpu to allocate to the ECS task | `number` | `1024` | no |
| <a name="input_task_cpu_architecture"></a> [task\_cpu\_architecture](#input\_task\_cpu\_architecture) | The CPU architecture to use for the ECS task | `string` | `"X86_64"` | no |
| <a name="input_task_desired_count"></a> [task\_desired\_count](#input\_task\_desired\_count) | How many load generator tasks to run. Each one produces start\_rate process instances per second, so the total rate is the product of the two. | `number` | `1` | no |
| <a name="input_task_enable_execute_command"></a> [task\_enable\_execute\_command](#input\_task\_enable\_execute\_command) | Whether to enable execute command for the ECS service | `bool` | `false` | no |
| <a name="input_task_memory"></a> [task\_memory](#input\_task\_memory) | The amount of memory to allocate to the ECS task | `number` | `2048` | no |
| <a name="input_task_operating_system_family"></a> [task\_operating\_system\_family](#input\_task\_operating\_system\_family) | The operating system family to use for the ECS task | `string` | `"LINUX"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC id where the ECS cluster and service are deployed | `string` | n/a | yes |
| <a name="input_vpc_private_subnets"></a> [vpc\_private\_subnets](#input\_vpc\_private\_subnets) | List of private subnet IDs within the VPC | `list(string)` | n/a | yes |
| <a name="input_wait_for_steady_state"></a> [wait\_for\_steady\_state](#input\_wait\_for\_steady\_state) | Whether to wait for the ECS service to reach a steady state after deployment | `bool` | `false` | no |
| <a name="input_warmup_phase_duration_millis"></a> [warmup\_phase\_duration\_millis](#input\_warmup\_phase\_duration\_millis) | Milliseconds of warm-up before the generator holds its target rate. | `number` | `10000` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_grpc_address"></a> [grpc\_address](#output\_grpc\_address) | The gRPC address the generator drives load against |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | The name of the CloudWatch log group the generator logs to. Its throughput lines are the signal this module exists to produce. |
| <a name="output_rest_address"></a> [rest\_address](#output\_rest\_address) | The REST address the generator drives load against |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | The name of the load generator ECS service |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | The ARN of the load generator task definition |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | The ARN of the IAM role assumed by the load generator task |
<!-- END_TF_DOCS -->
