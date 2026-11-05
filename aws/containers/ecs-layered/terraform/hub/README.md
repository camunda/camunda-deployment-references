# Camunda Hub layer

One Camunda Hub for the whole estate. It connects to every Orchestration Cluster listed in `clusters`; adding a cluster is adding an entry, not another Hub.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_camunda_hub"></a> [camunda\_hub](#module\_camunda\_hub) | ../../../../modules/ecs/fargate/camunda-hub | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.secrets_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role_policy_attachment.secrets_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_secretsmanager_secret.license_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.pusher_app_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.pusher_app_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.license_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.pusher_app_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.pusher_app_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [random_password.pusher_app_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.pusher_app_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [terraform_data.database_ready](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_listener_http_webapp_arn"></a> [alb\_listener\_http\_webapp\_arn](#input\_alb\_listener\_http\_webapp\_arn) | Exposure layer output: listener Camunda Hub attaches its rules to | `string` | n/a | yes |
| <a name="input_camunda_license_key"></a> [camunda\_license\_key](#input\_camunda\_license\_key) | License key. Stored in Secrets Manager and injected as CAMUNDA\_LICENSE\_KEY. Empty runs Camunda Hub in its trial mode. | `string` | `""` | no |
| <a name="input_camunda_ports_security_group_id"></a> [camunda\_ports\_security\_group\_id](#input\_camunda\_ports\_security\_group\_id) | Compute layer output: security group that opens the ports inside the VPC | `string` | n/a | yes |
| <a name="input_clusters"></a> [clusters](#input\_clusters) | The Orchestration Clusters that this Camunda Hub connects to, by ID. Take each entry from the cluster\_registration output of the Camunda layer of that cluster. One Camunda Hub serves all of them. | <pre>map(object({<br/>    name          = optional(string, "")<br/>    version       = string<br/>    rest_url      = string<br/>    grpc_url      = string<br/>    readiness_url = string<br/>  }))</pre> | n/a | yes |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | Context path Camunda Hub is served under on the load balancer. The websocket relay is served under <context\_path>-ws. | `string` | `"/hub"` | no |
| <a name="input_database"></a> [database](#input\_database) | Storage layer output databases["camunda\_hub"], declared with auth = iam | <pre>object({<br/>    database_name      = string<br/>    username           = string<br/>    jdbc_url           = string<br/>    connect_policy_arn = string<br/>  })</pre> | n/a | yes |
| <a name="input_db_seed_done"></a> [db\_seed\_done](#input\_db\_seed\_done) | Storage layer output: changes once the database exists. Only used to order the deployment. | `string` | `""` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | Compute layer output: ID of the ECS cluster | `string` | n/a | yes |
| <a name="input_egress_security_group_id"></a> [egress\_security\_group\_id](#input\_egress\_security\_group\_id) | Compute layer output: security group that allows outbound HTTP and HTTPS | `string` | n/a | yes |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | Compute layer output components\_log\_group\_name | `string` | n/a | yes |
| <a name="input_mail_from_address"></a> [mail\_from\_address](#input\_mail\_from\_address) | Sender address of invitation mails. The application requires one. Without an SMTP host, invitations aren't sent. | `string` | `"changeme@example.com"` | no |
| <a name="input_management_identity_hub_authorization_enabled"></a> [management\_identity\_hub\_authorization\_enabled](#input\_management\_identity\_hub\_authorization\_enabled) | Management Identity layer output hub\_authorization\_enabled. It must be true: otherwise Camunda Hub signs in but every authorization check is denied. | `bool` | n/a | yes |
| <a name="input_management_identity_url"></a> [management\_identity\_url](#input\_management\_identity\_url) | Management Identity layer output internal\_url: where Camunda Hub asks for roles and organizations | `string` | n/a | yes |
| <a name="input_oidc"></a> [oidc](#input\_oidc) | OIDC provider layer output management. It can also describe an OIDC provider that you run yourself, with a public client for Camunda Hub and the two audiences. | <pre>object({<br/>    issuer_uri         = string<br/>    issuer_backend_uri = string<br/>    hub = object({<br/>      client_id         = string<br/>      audience_internal = string<br/>      audience_public   = string<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Network layer output: private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_public_base_url"></a> [public\_base\_url](#input\_public\_base\_url) | Exposure layer output: browser-facing base URL, for the login redirect and the websocket host | `string` | n/a | yes |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | Compute layer output: registry credentials secret. It is only attached to images that come from the private Camunda registry. | `string` | `""` | no |
| <a name="input_restapi_image"></a> [restapi\_image](#input\_restapi\_image) | Image of the Camunda Hub REST API and web UI. Registry credentials are attached only if it comes from registry.camunda.cloud. | `string` | `"camunda/hub:8.10.4"` | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Compute layer output: KMS key that encrypts the secrets | `string` | n/a | yes |
| <a name="input_service_connect_namespace_arn"></a> [service\_connect\_namespace\_arn](#input\_service\_connect\_namespace\_arn) | Compute layer output: Service Connect namespace shared by the management plane components | `string` | n/a | yes |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | Compute layer output: ARN of the task execution role | `string` | n/a | yes |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Compute layer output: name of the task execution role, to attach the secret read policy of this layer | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Network layer output: ID of the VPC | `string` | n/a | yes |
| <a name="input_websockets_image"></a> [websockets\_image](#input\_websockets\_image) | Image of the Camunda Hub websocket relay. Registry credentials are attached only if it comes from registry.camunda.cloud. | `string` | `"camunda/hub-websockets:8.10.4"` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_clusters"></a> [clusters](#output\_clusters) | IDs of the Orchestration Clusters that Camunda Hub is connected to |
| <a name="output_clusters_config"></a> [clusters\_config](#output\_clusters\_config) | The Orchestration Clusters as Camunda Hub is configured with them |
| <a name="output_public_url"></a> [public\_url](#output\_public\_url) | Browser-facing address of Camunda Hub. Register it as the login redirect in an OIDC provider that you run yourself: <public\_url>/login-callback. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the Camunda Hub ECS service |
<!-- END_TF_DOCS -->
