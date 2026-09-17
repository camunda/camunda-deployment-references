# monitoring

A long-lived Prometheus for Orchestration Clusters running on ECS Fargate.

Prometheus has no equivalent of the Kubernetes service-discovery roles on ECS,
and hardcoding task IPs does not survive a redeployment. This module ships the
server with a sidecar that queries AWS Cloud Map for orchestration clusters and
rewrites a `file_sd_configs` target list, which Prometheus hot-reloads. Deploy
or destroy a cluster and the target list follows within one refresh interval,
with no change here.

Absorbed from [`camunda/camunda-load-tests-ecs`](https://github.com/camunda/camunda-load-tests-ecs),
where it answered the "persistent performance monitoring" half of
[team-infrastructure-experience#464](https://github.com/camunda/team-infrastructure-experience/issues/464).

## Usage

```hcl
module "monitoring" {
  source = "../../../../modules/ecs/fargate/monitoring"

  prefix              = "camunda-lt"
  ecs_cluster_id      = aws_ecs_cluster.ecs.id
  vpc_id              = module.vpc.vpc_id
  vpc_private_subnets = module.vpc.private_subnets
  aws_region          = data.aws_region.current.region

  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]
}
```

The service needs egress to the metrics port inside the VPC to scrape, and
egress on 443 to reach the Cloud Map API.

## What it does not do

**No public endpoint by default.** Prometheus serves an unauthenticated read of
everything it has scraped, so `enable_alb_http_listener_rule` is `false` and the
server is reachable only through its private DNS name. The repository this came
from put it behind an internet-facing ALB; that is available here by passing a
listener ARN, but it is a decision you make rather than one you inherit.

**No persistence.** Samples live on the task's ephemeral storage, so a restart
starts an empty series and `desired_count` is fixed at one. `retention_time`
bounds how far back the server can look, not how long the data survives. Point
a remote-write target at it for anything that has to outlive the task.

**No cross-account or cross-cloud federation.** The absorbed version carried a
security group admitting GCP CIDRs over a site-to-site VPN, whose source of
truth was a file in a private Camunda repository. That is infrastructure
specific to Camunda's own benchmark environment, not something a reader of this
repository can use, so it was dropped.

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_service.prometheus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.prometheus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.cloudmap_discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ecs_exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cloudmap_discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lb_listener_rule.prometheus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.prometheus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_service_discovery_private_dns_namespace.namespace](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_private_dns_namespace) | resource |
| [aws_service_discovery_service.prometheus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_service) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_listener_http_arn"></a> [alb\_listener\_http\_arn](#input\_alb\_listener\_http\_arn) | The ARN of the ALB listener to attach the Prometheus rule to. Required when enable\_alb\_http\_listener\_rule is true. | `string` | `""` | no |
| <a name="input_alb_listener_rule_path_pattern"></a> [alb\_listener\_rule\_path\_pattern](#input\_alb\_listener\_rule\_path\_pattern) | The path pattern the ALB listener rule matches on. | `string` | `"/prometheus/*"` | no |
| <a name="input_alb_listener_rule_priority"></a> [alb\_listener\_rule\_priority](#input\_alb\_listener\_rule\_priority) | The priority of the ALB listener rule created for Prometheus. | `number` | `100` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | The AWS region to deploy resources in | `string` | n/a | yes |
| <a name="input_discovery_image"></a> [discovery\_image](#input\_discovery\_image) | The container image used by the Cloud Map discovery sidecar. It only needs the AWS CLI. | `string` | `"amazon/aws-cli:2.32.7"` | no |
| <a name="input_discovery_namespace_suffix"></a> [discovery\_namespace\_suffix](#input\_discovery\_namespace\_suffix) | Only Cloud Map private DNS namespaces whose name ends with this suffix are scraped. The orchestration-cluster module registers '<prefix>.service.local'. | `string` | `".service.local"` | no |
| <a name="input_discovery_refresh_interval_seconds"></a> [discovery\_refresh\_interval\_seconds](#input\_discovery\_refresh\_interval\_seconds) | How often the sidecar re-queries Cloud Map. Prometheus hot-reloads the file it writes, so this is also how quickly a new cluster starts being scraped. | `number` | `30` | no |
| <a name="input_discovery_service_name"></a> [discovery\_service\_name](#input\_discovery\_service\_name) | The Cloud Map service name to look for inside each matching namespace. | `string` | `"orchestration-cluster"` | no |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | The cluster id of the ECS cluster to spawn the ECS service in | `string` | n/a | yes |
| <a name="input_ecs_task_execution_role_arn"></a> [ecs\_task\_execution\_role\_arn](#input\_ecs\_task\_execution\_role\_arn) | ARN of the ECS task execution role (centrally managed) | `string` | n/a | yes |
| <a name="input_enable_alb_http_listener_rule"></a> [enable\_alb\_http\_listener\_rule](#input\_enable\_alb\_http\_listener\_rule) | Whether to expose Prometheus through an existing ALB listener. Off by default: the endpoint is unauthenticated, so it stays reachable only from inside the VPC unless you opt in. | `bool` | `false` | no |
| <a name="input_image"></a> [image](#input\_image) | The container image to use for Prometheus | `string` | `"prom/prometheus:v3.11.2"` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | The name of an existing CloudWatch log group for the ECS tasks. When empty, the module creates its own log group. | `string` | `""` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | Retention of the CloudWatch log group created by this module. Ignored when log\_group\_name is supplied. | `number` | `7` | no |
| <a name="input_metrics_path"></a> [metrics\_path](#input\_metrics\_path) | The HTTP path the discovered targets expose their metrics on. | `string` | `"/actuator/prometheus"` | no |
| <a name="input_metrics_port"></a> [metrics\_port](#input\_metrics\_port) | The port the discovered targets expose their metrics on. Matches the Camunda management port. | `number` | `9600` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for naming resources | `string` | n/a | yes |
| <a name="input_prometheus_port"></a> [prometheus\_port](#input\_prometheus\_port) | The port Prometheus listens on | `number` | `9090` | no |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | The ARN of the Secrets Manager secret containing registry credentials, when the images are pulled from a private registry | `string` | `""` | no |
| <a name="input_retention_time"></a> [retention\_time](#input\_retention\_time) | How long Prometheus keeps samples on local storage, as a Prometheus duration (for example 168h, 15d, 4w). | `string` | `"168h"` | no |
| <a name="input_scrape_interval"></a> [scrape\_interval](#input\_scrape\_interval) | The global Prometheus scrape interval, as a Prometheus duration. | `string` | `"15s"` | no |
| <a name="input_service_force_new_deployment"></a> [service\_force\_new\_deployment](#input\_service\_force\_new\_deployment) | Whether to force a new deployment of the ECS service | `bool` | `false` | no |
| <a name="input_service_security_group_ids"></a> [service\_security\_group\_ids](#input\_service\_security\_group\_ids) | List of security group IDs to associate with the ECS service | `list(string)` | `[]` | no |
| <a name="input_service_timeouts"></a> [service\_timeouts](#input\_service\_timeouts) | Timeout configuration for ECS service operations | <pre>object({<br/>    create = optional(string, "15m")<br/>    update = optional(string, "30m")<br/>    delete = optional(string, "20m")<br/>  })</pre> | <pre>{<br/>  "create": "15m",<br/>  "delete": "20m",<br/>  "update": "30m"<br/>}</pre> | no |
| <a name="input_task_cpu"></a> [task\_cpu](#input\_task\_cpu) | The amount of cpu to allocate to the ECS task | `number` | `512` | no |
| <a name="input_task_cpu_architecture"></a> [task\_cpu\_architecture](#input\_task\_cpu\_architecture) | The CPU architecture to use for the ECS task | `string` | `"X86_64"` | no |
| <a name="input_task_enable_execute_command"></a> [task\_enable\_execute\_command](#input\_task\_enable\_execute\_command) | Whether to enable execute command for the ECS service | `bool` | `false` | no |
| <a name="input_task_memory"></a> [task\_memory](#input\_task\_memory) | The amount of memory to allocate to the ECS task | `number` | `1024` | no |
| <a name="input_task_operating_system_family"></a> [task\_operating\_system\_family](#input\_task\_operating\_system\_family) | The operating system family to use for the ECS task | `string` | `"LINUX"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC id where the ECS cluster and service are deployed | `string` | n/a | yes |
| <a name="input_vpc_private_subnets"></a> [vpc\_private\_subnets](#input\_vpc\_private\_subnets) | List of private subnet IDs within the VPC | `list(string)` | n/a | yes |
| <a name="input_wait_for_steady_state"></a> [wait\_for\_steady\_state](#input\_wait\_for\_steady\_state) | Whether to wait for the ECS service to reach a steady state after deployment | `bool` | `true` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dns_a_record"></a> [dns\_a\_record](#output\_dns\_a\_record) | The private DNS name the Prometheus service registers in Cloud Map |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | The name of the CloudWatch log group the monitoring task logs to |
| <a name="output_prometheus_endpoint"></a> [prometheus\_endpoint](#output\_prometheus\_endpoint) | The in-VPC base URL of the Prometheus server |
| <a name="output_prometheus_port"></a> [prometheus\_port](#output\_prometheus\_port) | The port Prometheus listens on |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | The name of the Prometheus ECS service |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | The ARN of the ALB target group, when Prometheus is exposed through a listener |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | The ARN of the IAM role assumed by the Prometheus task |
<!-- END_TF_DOCS -->
