# AWS Cognito Test Module

This Terraform module creates a temporary AWS Cognito User Pool with the required configuration for testing Camunda Platform with OIDC authentication.

## Purpose

This module is designed for:
- **Integration testing**: Create isolated Cognito user pools for CI/CD pipelines
- **Development**: Quick setup of OIDC authentication for local development
- **Temporary environments**: Auto-cleanup tracking for ephemeral environments

## Features

- ✅ Cognito User Pool with email-based authentication
- ✅ Pre-configured OIDC clients for all Camunda components
- ✅ Optional test user creation for automated testing
- ✅ Support for WebModeler and Console components
- ✅ M2M (machine-to-machine) client for Connectors
- ✅ Auto-cleanup tracking via tags

## Usage

```hcl
module "cognito_test" {
  source = "./aws/common/cognito"

  resource_prefix    = "my-test-cluster"
  domain_name        = "camunda.example.com"
  enable_webmodeler  = true
  enable_console     = true
  create_test_user   = true
  test_user_name     = "test@example.com"
  test_user_password = "SecureP@ssw0rd123!"
  auto_cleanup_hours = 72
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `resource_prefix` | Prefix for Cognito resources | `string` | `"camunda-test"` | no |
| `domain_name` | Domain name for Camunda deployment | `string` | `""` | no |
| `enable_webmodeler` | Enable Web Modeler component | `bool` | `false` | no |
| `enable_console` | Enable Console component | `bool` | `false` | no |
| `create_test_user` | Create a test user | `bool` | `false` | no |
| `test_user_name` | Email for the test user | `string` | `"camunda-test@example.com"` | no |
| `test_user_password` | Password for the test user | `string` | `"CamundaTest123!"` | no |
| `mfa_enabled` | Enable MFA (OPTIONAL mode) | `bool` | `false` | no |
| `auto_cleanup_hours` | Cleanup tracking hours | `number` | `72` | no |
| `tags` | Additional tags | `map(string)` | `{}` | no |

## Outputs

### OIDC Endpoints

| Name | Description |
|------|-------------|
| `issuer_url` | OIDC Issuer URL |
| `authorization_url` | OAuth2 Authorization endpoint |
| `token_url` | OAuth2 Token endpoint |
| `jwks_url` | JWKS endpoint |
| `userinfo_url` | UserInfo endpoint |

### Client Credentials

Each Camunda component has its own client:
- `identity_client_id` / `identity_client_secret`
- `optimize_client_id` / `optimize_client_secret`
- `orchestration_client_id` / `orchestration_client_secret`
- `connectors_client_id` / `connectors_client_secret`
- `webmodeler_api_client_id` / `webmodeler_api_client_secret`
- `console_client_id` (public client, no secret)
- `webmodeler_ui_client_id` (public client, no secret)

## Comparison with EntraID Module

| Feature | Cognito | EntraID |
|---------|---------|---------|
| Provider | AWS | Azure |
| User Pool/Directory | Cognito User Pool | Azure AD Tenant |
| Domain | `*.auth.<region>.amazoncognito.com` | `login.microsoftonline.com` |
| M2M Auth | Client Credentials via Resource Server | Application Permissions |
| Test User | Easy creation via `aws_cognito_user` | Requires User.ReadWrite.All |

## CI/CD Integration

This module is used by the GitHub Actions workflow via:
- `.github/actions/aws-cognito-create/` - Creates Cognito resources
- `.github/actions/aws-generic-terraform-cleanup/` - Destroys Cognito resources (generic Terraform cleanup)

## Notes

- Cognito domains must be globally unique across all AWS accounts
- The module automatically generates a random suffix to ensure uniqueness
- Test users are created with a permanent password (no force change on first login)

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_cognito_resource_server.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_resource_server) | resource |
| [aws_cognito_user.test](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user) | resource |
| [aws_cognito_user_pool.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool) | resource |
| [aws_cognito_user_pool_client.connectors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.console](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.identity](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.optimize](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.orchestration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.webmodeler_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.webmodeler_ui](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_domain.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_domain) | resource |
| [null_resource.cleanup_marker](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_static.creation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_auto_cleanup_hours"></a> [auto\_cleanup\_hours](#input\_auto\_cleanup\_hours) | Hours after which this Cognito pool should be automatically cleaned up (for CI tracking) | `number` | `72` | no |
| <a name="input_create_test_user"></a> [create\_test\_user](#input\_create\_test\_user) | Create a test user for simulating human login | `bool` | `false` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Bare hostname for Camunda deployment (e.g., my-cluster.camunda.example.com). No protocol, no trailing slash. Used to construct OIDC callback URLs. | `string` | `""` | no |
| <a name="input_enable_console"></a> [enable\_console](#input\_enable\_console) | Enable Console component (creates additional client) | `bool` | `false` | no |
| <a name="input_enable_webmodeler"></a> [enable\_webmodeler](#input\_enable\_webmodeler) | Enable Web Modeler component (creates additional client) | `bool` | `false` | no |
| <a name="input_mfa_enabled"></a> [mfa\_enabled](#input\_mfa\_enabled) | Enable MFA for Cognito users (OPTIONAL mode) | `bool` | `false` | no |
| <a name="input_resource_prefix"></a> [resource\_prefix](#input\_resource\_prefix) | Prefix for Cognito resources. If empty, uses 'camunda-test' | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for resources | `map(string)` | `{}` | no |
| <a name="input_test_user_name"></a> [test\_user\_name](#input\_test\_user\_name) | Email/Username for the test user | `string` | `"camunda-test@example.com"` | no |
| <a name="input_test_user_password"></a> [test\_user\_password](#input\_test\_user\_password) | Password for the test user (must meet Cognito password policy) | `string` | `"CamundaTest123!"` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_authorization_url"></a> [authorization\_url](#output\_authorization\_url) | OIDC Authorization endpoint |
| <a name="output_aws_region"></a> [aws\_region](#output\_aws\_region) | AWS Region where Cognito is deployed |
| <a name="output_cognito_domain"></a> [cognito\_domain](#output\_cognito\_domain) | Cognito User Pool domain prefix |
| <a name="output_connectors_client_id"></a> [connectors\_client\_id](#output\_connectors\_client\_id) | Connectors App Client ID |
| <a name="output_connectors_client_secret"></a> [connectors\_client\_secret](#output\_connectors\_client\_secret) | Connectors App Client Secret |
| <a name="output_console_client_id"></a> [console\_client\_id](#output\_console\_client\_id) | Console App Client ID (empty if not enabled) |
| <a name="output_created_at"></a> [created\_at](#output\_created\_at) | Timestamp when this Cognito pool was created |
| <a name="output_expires_at"></a> [expires\_at](#output\_expires\_at) | Timestamp when this Cognito pool should be cleaned up |
| <a name="output_identity_client_id"></a> [identity\_client\_id](#output\_identity\_client\_id) | Identity App Client ID |
| <a name="output_identity_client_secret"></a> [identity\_client\_secret](#output\_identity\_client\_secret) | Identity App Client Secret |
| <a name="output_issuer_url"></a> [issuer\_url](#output\_issuer\_url) | OIDC Issuer URL |
| <a name="output_jwks_url"></a> [jwks\_url](#output\_jwks\_url) | OIDC JWKS endpoint |
| <a name="output_logout_url"></a> [logout\_url](#output\_logout\_url) | Logout endpoint |
| <a name="output_oidc_config"></a> [oidc\_config](#output\_oidc\_config) | Complete OIDC configuration for Camunda |
| <a name="output_optimize_client_id"></a> [optimize\_client\_id](#output\_optimize\_client\_id) | Optimize App Client ID |
| <a name="output_optimize_client_secret"></a> [optimize\_client\_secret](#output\_optimize\_client\_secret) | Optimize App Client Secret |
| <a name="output_orchestration_client_id"></a> [orchestration\_client\_id](#output\_orchestration\_client\_id) | Orchestration App Client ID |
| <a name="output_orchestration_client_secret"></a> [orchestration\_client\_secret](#output\_orchestration\_client\_secret) | Orchestration App Client Secret |
| <a name="output_resource_server_identifier"></a> [resource\_server\_identifier](#output\_resource\_server\_identifier) | Resource Server identifier (used as scope prefix) |
| <a name="output_test_user_name"></a> [test\_user\_name](#output\_test\_user\_name) | Username (email) of the test user |
| <a name="output_test_user_password"></a> [test\_user\_password](#output\_test\_user\_password) | Password of the test user |
| <a name="output_token_url"></a> [token\_url](#output\_token\_url) | OIDC Token endpoint |
| <a name="output_user_pool_arn"></a> [user\_pool\_arn](#output\_user\_pool\_arn) | Cognito User Pool ARN |
| <a name="output_user_pool_endpoint"></a> [user\_pool\_endpoint](#output\_user\_pool\_endpoint) | Cognito User Pool endpoint |
| <a name="output_user_pool_id"></a> [user\_pool\_id](#output\_user\_pool\_id) | Cognito User Pool ID |
| <a name="output_userinfo_url"></a> [userinfo\_url](#output\_userinfo\_url) | OIDC UserInfo endpoint |
| <a name="output_webmodeler_api_client_id"></a> [webmodeler\_api\_client\_id](#output\_webmodeler\_api\_client\_id) | WebModeler API App Client ID (empty if not enabled) |
| <a name="output_webmodeler_api_client_secret"></a> [webmodeler\_api\_client\_secret](#output\_webmodeler\_api\_client\_secret) | WebModeler API App Client Secret (empty if not enabled) |
| <a name="output_webmodeler_ui_client_id"></a> [webmodeler\_ui\_client\_id](#output\_webmodeler\_ui\_client\_id) | WebModeler UI App Client ID (empty if not enabled) |
<!-- END_TF_DOCS -->
