# terraform

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_connectors"></a> [connectors](#module\_connectors) | ../../../modules/ecs/fargate/connectors | n/a |
| <a name="module_orchestration_cluster"></a> [orchestration\_cluster](#module\_orchestration\_cluster) | ../../../modules/ecs/fargate/orchestration-cluster | n/a |
| <a name="module_postgresql"></a> [postgresql](#module\_postgresql) | ../../../modules/aurora | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | v6.5.1 |
## Resources

| Name | Type |
|------|------|
| [aws_ecs_cluster.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_iam_policy.registry_secrets_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_lb.grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http_80](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_secretsmanager_secret.registry_credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.registry_credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.allow_necessary_camunda_ports_within_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_package_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_9600](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_blocks"></a> [cidr\_blocks](#input\_cidr\_blocks) | The CIDR block to use for the VPC | `string` | `"10.200.0.0/24"` | no |
| <a name="input_limit_access_to_cidrs"></a> [limit\_access\_to\_cidrs](#input\_limit\_access\_to\_cidrs) | List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_ports"></a> [ports](#input\_ports) | The ports to open for the security groups within the VPC | `map(number)` | <pre>{<br/>  "camunda_metrics_endpoint": 9600,<br/>  "camunda_web_ui": 8080,<br/>  "postgresql": 5432,<br/>  "zeebe_broker_network_command_api_port": 26501,<br/>  "zeebe_gateway_cluster_port": 26502,<br/>  "zeebe_gateway_network_port": 26500<br/>}</pre> | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for names of resources | `string` | `"camunda"` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | (Optional) The password for the container registry (e.g., Docker Hub) | `string` | `""` | no |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | (Optional) The username for the container registry (e.g., Docker Hub) | `string` | `""` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_endpoint"></a> [alb\_endpoint](#output\_alb\_endpoint) | (Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp. |
| <a name="output_nlb_endpoint"></a> [nlb\_endpoint](#output\_nlb\_endpoint) | (Optional) The DNS name of the Network Load Balancer (NLB) to access the Camunda Core. |
<!-- END_TF_DOCS -->
