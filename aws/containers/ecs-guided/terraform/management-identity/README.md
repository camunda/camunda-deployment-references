# Management Identity stage

Management Identity of the management plane: the permission model that Camunda Hub resolves its authorization through. With `enable_hub_authorization` it declares the Web Modeler roles and grants them to the administrator.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_management_identity"></a> [management\_identity](#module\_management\_identity) | ../../../../modules/ecs/fargate/management-identity | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.client_secret_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role_policy_attachment.client_secret_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [terraform_data.database_ready](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_listener_http_webapp_arn"></a> [alb\_listener\_http\_webapp\_arn](#input\_alb\_listener\_http\_webapp\_arn) | Exposure stage output: listener Management Identity attaches its rule to | `string` | n/a | yes |
| <a name="input_camunda_ports_security_group_id"></a> [camunda\_ports\_security\_group\_id](#input\_camunda\_ports\_security\_group\_id) | Compute stage output: security group that opens the ports inside the VPC | `string` | n/a | yes |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | Context path Management Identity is served under on the load balancer | `string` | `"/identity"` | no |
| <a name="input_database"></a> [database](#input\_database) | Storage stage output databases["management\_identity"], declared with auth = iam | <pre>object({<br/>    database_name      = string<br/>    username           = string<br/>    jdbc_url           = string<br/>    connect_policy_arn = string<br/>  })</pre> | n/a | yes |
| <a name="input_db_seed_done"></a> [db\_seed\_done](#input\_db\_seed\_done) | Storage stage output: changes once the database exists. Only used to order the deployment. | `string` | `""` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | Compute stage output: ID of the ECS cluster | `string` | n/a | yes |
| <a name="input_egress_security_group_id"></a> [egress\_security\_group\_id](#input\_egress\_security\_group\_id) | Compute stage output: security group that allows outbound HTTP and HTTPS | `string` | n/a | yes |
| <a name="input_enable_hub_authorization"></a> [enable\_hub\_authorization](#input\_enable\_hub\_authorization) | Declare the roles Camunda Hub needs (Web Modeler, Web Modeler Admin) and grant them to the administrator. Turn it on when Camunda Hub uses this Management Identity: without it Hub signs in, but every authorization check is denied. | `bool` | `false` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | Compute stage output components\_log\_group\_name | `string` | n/a | yes |
| <a name="input_oidc"></a> [oidc](#input\_oidc) | OIDC provider stage output management. It can also describe an OIDC provider that you run yourself, as long as it has the client that identity names and the audiences. | <pre>object({<br/>    issuer_uri         = string<br/>    issuer_backend_uri = string<br/>    username_claim     = string<br/>    admin_claim        = string<br/>    identity = object({<br/>      client_id         = string<br/>      client_secret_arn = string<br/>      audience          = string<br/>    })<br/>    hub = object({<br/>      client_id         = string<br/>      audience_internal = string<br/>      audience_public   = string<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Network stage output: private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_public_base_url"></a> [public\_base\_url](#input\_public\_base\_url) | Exposure stage output: browser-facing base URL | `string` | n/a | yes |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | Compute stage output: registry credentials secret, empty for public images | `string` | `""` | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Compute stage output: KMS key that encrypts the secrets | `string` | n/a | yes |
| <a name="input_service_connect_namespace_arn"></a> [service\_connect\_namespace\_arn](#input\_service\_connect\_namespace\_arn) | Compute stage output: Service Connect namespace shared by the management plane components | `string` | n/a | yes |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | Compute stage output: ARN of the task execution role | `string` | n/a | yes |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Compute stage output: name of the task execution role, to attach the secret read policy of this stage | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Network stage output: ID of the VPC | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_authorization"></a> [authorization](#output\_authorization) | The authorization model that Management Identity is seeded with (presets and mapping rule), or null when enable\_hub\_authorization is false |
| <a name="output_hub_authorization_enabled"></a> [hub\_authorization\_enabled](#output\_hub\_authorization\_enabled) | Whether the roles Camunda Hub needs are declared. The Camunda Hub stage requires true. |
| <a name="output_identity_service_connect"></a> [identity\_service\_connect](#output\_identity\_service\_connect) | Service Connect name of Management Identity |
| <a name="output_internal_url"></a> [internal\_url](#output\_internal\_url) | Address of Management Identity inside the ECS cluster, with its context path. Camunda Hub calls it. |
| <a name="output_public_url"></a> [public\_url](#output\_public\_url) | Browser-facing address of Management Identity |
<!-- END_TF_DOCS -->
