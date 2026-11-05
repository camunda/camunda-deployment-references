# Identity layer

`basic` (built-in users) or `oidc` (your provider). Produces one `oidc` object, or `null`, that the Camunda layer reads. An OIDC provider deployed on ECS by this architecture is parked: it would be a second producer of the same `oidc` object.

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.client_secrets_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role_policy_attachment.client_secrets_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [terraform_data.validate](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_claim_value"></a> [admin\_claim\_value](#input\_admin\_claim\_value) | Value of the username claim that identifies the administrator. Set it to a principal that exists in your directory, otherwise nobody gets the admin role. | `string` | `"admin"` | no |
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | basic: built-in users, no identity provider. oidc: your OIDC provider, described by external\_oidc. | `string` | `"basic"` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_external_oidc"></a> [external\_oidc](#input\_external\_oidc) | Your OIDC provider. Required when authentication\_mode = oidc. Client secrets are existing Secrets Manager ARNs, never raw values, and must be encrypted with the AWS managed key or with the secrets\_kms\_key\_arn of the compute layer, otherwise the task cannot decrypt them. | <pre>object({<br/>    issuer_uri             = string<br/>    token_uri              = string<br/>    orchestration_audience = string<br/><br/>    orchestration_client_id         = string<br/>    orchestration_client_secret_arn = string<br/>    connectors_client_id            = string<br/>    connectors_client_secret_arn    = string<br/><br/>    # Claim names. The defaults are the most common claim names; Entra ID, for one, identifies the<br/>    # calling application with azp or appid instead of client_id.<br/>    username_claim  = optional(string, "preferred_username")<br/>    client_id_claim = optional(string, "client_id")<br/><br/>    # Scope for the connectors client-credentials request. Entra ID v2 needs <resource>/.default.<br/>    connectors_token_scope = optional(string, "")<br/><br/>    # KMS key the client secrets are encrypted with, when it is not the key of the compute layer<br/>    # (for example when an OIDC provider of the management plane created them). Empty uses the key of<br/>    # the compute layer.<br/>    client_secrets_kms_key_arn = optional(string, "")<br/>  })</pre> | `null` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_public_base_url"></a> [public\_base\_url](#input\_public\_base\_url) | Exposure layer output: browser-facing base URL. The OIDC redirect URI (<base>/sso-callback) is built from it. Required when authentication\_mode = oidc. | `string` | `""` | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Compute layer output: KMS key the client secrets are encrypted with. Required when authentication\_mode = oidc. | `string` | `""` | no |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Compute layer output: execution role that reads the client secrets. Required when authentication\_mode = oidc. | `string` | `""` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_authentication_mode"></a> [authentication\_mode](#output\_authentication\_mode) | basic or oidc |
| <a name="output_oidc"></a> [oidc](#output\_oidc) | Identity contract. null in basic mode, otherwise the OIDC settings every component reads: issuer\_uri, token\_uri, audience, redirect\_uri, claim names, and one client (id and secret ARN) per component. |
<!-- END_TF_DOCS -->
