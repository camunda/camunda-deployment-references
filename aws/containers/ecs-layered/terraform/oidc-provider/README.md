# OIDC provider layer

An OIDC provider on ECS for the management plane. It imports a realm on first start with one orchestration and one connectors client for each Orchestration Cluster in `clusters`, the Management Identity client, and the Camunda Hub client. Its `clusters` output is the `external_oidc` object of the identity layer of each cluster, and its `management` output is what Management Identity and Camunda Hub read.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_oidc_provider"></a> [oidc\_provider](#module\_oidc\_provider) | ../../../../modules/ecs/fargate/keycloak | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.secrets_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role_policy_attachment.secrets_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_secretsmanager_secret.bootstrap_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.connectors_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.identity_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.orchestration_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.realm_admin_user](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.realm_import](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.bootstrap_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.connectors_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.identity_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.orchestration_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.realm_admin_user](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.realm_import](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [random_password.bootstrap_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.connectors_client](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.identity_client](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.orchestration_client](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.realm_admin_user](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [terraform_data.database_ready](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Login user of the realm. It is the administrator of the platform: its username claim receives the admin roles. | `string` | `"admin"` | no |
| <a name="input_alb_listener_http_webapp_arn"></a> [alb\_listener\_http\_webapp\_arn](#input\_alb\_listener\_http\_webapp\_arn) | Exposure layer output: listener the OIDC provider attaches its rule to | `string` | n/a | yes |
| <a name="input_camunda_ports_security_group_id"></a> [camunda\_ports\_security\_group\_id](#input\_camunda\_ports\_security\_group\_id) | Compute layer output: security group that opens the ports inside the VPC | `string` | n/a | yes |
| <a name="input_clusters"></a> [clusters](#input\_clusters) | The Orchestration Clusters that use this provider, by name. Each gets its own orchestration and connectors clients. base\_url is the public URL of the cluster, for the login redirect; empty uses public\_base\_url, which is right when the cluster shares the load balancer. The realm is imported when the provider starts for the first time: a cluster that you add later is registered in the provider's administration console with the values of the clusters output. | <pre>map(object({<br/>    base_url = optional(string, "")<br/>  }))</pre> | <pre>{<br/>  "default": {}<br/>}</pre> | no |
| <a name="input_database"></a> [database](#input\_database) | Storage layer output databases["oidc\_provider"], declared with auth = password | <pre>object({<br/>    database_name       = string<br/>    username            = string<br/>    jdbc_url            = string<br/>    password_secret_arn = string<br/>  })</pre> | n/a | yes |
| <a name="input_db_seed_done"></a> [db\_seed\_done](#input\_db\_seed\_done) | Storage layer output: changes once the database exists. Only used to order the deployment. | `string` | `""` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | Compute layer output: ID of the ECS cluster that runs the OIDC provider | `string` | n/a | yes |
| <a name="input_egress_security_group_id"></a> [egress\_security\_group\_id](#input\_egress\_security\_group\_id) | Compute layer output: security group that allows outbound HTTP and HTTPS | `string` | n/a | yes |
| <a name="input_enable_camunda_hub"></a> [enable\_camunda\_hub](#input\_enable\_camunda\_hub) | Register the Camunda Hub client in the realm | `bool` | `false` | no |
| <a name="input_hub_context_path"></a> [hub\_context\_path](#input\_hub\_context\_path) | Context path Camunda Hub is served under. The login redirect is built from it. | `string` | `"/hub"` | no |
| <a name="input_identity_context_path"></a> [identity\_context\_path](#input\_identity\_context\_path) | Context path Management Identity is served under. Its login redirect is built from it. | `string` | `"/identity"` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | Compute layer output components\_log\_group\_name | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Network layer output: private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_public_base_url"></a> [public\_base\_url](#input\_public\_base\_url) | Exposure layer output: browser-facing base URL of the load balancer that serves the management plane. The issuer is <public\_base\_url>/auth/realms/camunda-platform. | `string` | n/a | yes |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | Compute layer output: registry credentials secret, empty for public images | `string` | `""` | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Compute layer output: KMS key that encrypts the secrets | `string` | n/a | yes |
| <a name="input_service_connect_name"></a> [service\_connect\_name](#input\_service\_connect\_name) | Name under which the other components of the management plane reach the provider inside the ECS cluster | `string` | `"oidc-provider"` | no |
| <a name="input_service_connect_namespace_arn"></a> [service\_connect\_namespace\_arn](#input\_service\_connect\_namespace\_arn) | Compute layer output: Service Connect namespace shared by the management plane components | `string` | n/a | yes |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | Compute layer output: ARN of the task execution role | `string` | n/a | yes |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Compute layer output: name of the task execution role, to attach the secret read policy of this layer | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Network layer output: ID of the VPC | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admin_user_password"></a> [admin\_user\_password](#output\_admin\_user\_password) | Password of the realm login user, who administers the platform. Also stored in Secrets Manager. |
| <a name="output_clusters"></a> [clusters](#output\_clusters) | Per Orchestration Cluster: the values of the identity layer's external\_oidc, to pass to the identity layer of that cluster |
| <a name="output_issuer_uri"></a> [issuer\_uri](#output\_issuer\_uri) | OIDC issuer, as the browsers and the components see it |
| <a name="output_management"></a> [management](#output\_management) | What Management Identity and Camunda Hub read: the issuer, the administrator claim, and their clients and audiences |
| <a name="output_service_connect_name"></a> [service\_connect\_name](#output\_service\_connect\_name) | Name under which the components of the management plane reach the provider inside the ECS cluster |
<!-- END_TF_DOCS -->
