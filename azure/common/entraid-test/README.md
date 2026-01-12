# Temporary EntraID for Camunda Testing

This Terraform module creates a temporary Azure AD (EntraID) application registration for testing Camunda Platform with OIDC authentication.

## ⚠️ Important

**This module is for CI/CD testing only.** It creates temporary credentials with a limited lifespan.

For production deployments, users should:
- Use their own EntraID tenant
- Configure proper security policies
- Manage credentials according to their organization's policies

## Features

- Creates Azure AD App Registration with OIDC configuration
- Generates client secrets for all Camunda components
- Optionally creates a test admin user
- Automatic cleanup markers for CI/CD
- Isolated test environment (single tenant)

## Usage

```hcl
module "entraid_test" {
  source = "../../../azure/common/entraid-test"

  resource_prefix            = "camunda-test-${var.cluster_name}"
  domain_name                = "camunda-test.example.com"
  create_admin_user          = true
  admin_user_email           = "test-admin"
  admin_temporary_password   = var.admin_password
  enable_webmodeler          = true
  secret_validity_hours      = 168  # 7 days
  auto_cleanup_hours         = 72   # 3 days
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| azuread | ~> 2.47 |
| random | ~> 3.6 |
| time | ~> 0.10 |

## Providers

| Name | Version |
|------|---------|
| azuread | ~> 2.47 |
| random | ~> 3.6 |
| time | ~> 0.10 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_prefix | Prefix for EntraID resources | `string` | `""` | no |
| domain_name | Domain name for Camunda deployment | `string` | `""` | no |
| tenant_id | Azure AD Tenant ID | `string` | `""` | no |
| create_admin_user | Create initial admin user | `bool` | `true` | no |
| admin_user_email | Email prefix for admin user | `string` | `"camunda-admin-test"` | no |
| admin_temporary_password | Temporary password | `string` | `"TempP@ssw0rd123!"` | no |
| enable_webmodeler | Enable Web Modeler | `bool` | `false` | no |
| secret_validity_hours | Client secret validity in hours | `number` | `720` | no |
| auto_cleanup_hours | Auto-cleanup time in hours | `number` | `72` | no |

## Outputs

| Name | Description |
|------|-------------|
| tenant_id | Azure AD Tenant ID |
| client_id | Application (client) ID |
| issuer_url | OIDC Issuer URL |
| authorization_url | OIDC Authorization endpoint |
| token_url | OIDC Token endpoint |
| jwks_url | OIDC JWKS endpoint |
| identity_client_secret | Client secret for Identity (sensitive) |
| optimize_client_secret | Client secret for Optimize (sensitive) |
| orchestration_client_secret | Client secret for Orchestration (sensitive) |
| connectors_client_secret | Client secret for Connectors (sensitive) |
| oidc_config | Complete OIDC configuration |

## Cleanup

The module includes cleanup markers that can be used by CI/CD to automatically remove stale test resources:

```bash
# Find resources older than auto_cleanup_hours
terraform output expires_at
```

## Security Notes

1. **Secrets Rotation**: Client secrets have a configurable expiration
2. **Test Isolation**: Uses single-tenant sign-in audience
3. **Automatic Cleanup**: Includes expiration metadata
4. **Limited Scope**: Only requests necessary Microsoft Graph permissions

## License

Same as parent repository.

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [azuread_application.camunda](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_password.connectors](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_application_password.identity](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_application_password.optimize](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_application_password.orchestration](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_application_password.webmodeler_api](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_service_principal.camunda](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/service_principal) | resource |
| [azuread_user.admin](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/user) | resource |
| [null_resource.cleanup_marker](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_static.creation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
| [azuread_domains.aad_domains](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/domains) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_temporary_password"></a> [admin\_temporary\_password](#input\_admin\_temporary\_password) | Temporary password for the initial admin user (must be changed on first login) | `string` | `"TempP@ssw0rd123!"` | no |
| <a name="input_admin_user_email"></a> [admin\_user\_email](#input\_admin\_user\_email) | Email prefix for the initial admin user (will append tenant domain) | `string` | `"camunda-admin-test"` | no |
| <a name="input_auto_cleanup_hours"></a> [auto\_cleanup\_hours](#input\_auto\_cleanup\_hours) | Hours after which this EntraID app should be automatically cleaned up (for CI tracking) | `number` | `72` | no |
| <a name="input_create_admin_user"></a> [create\_admin\_user](#input\_create\_admin\_user) | Create an initial admin user in Azure AD | `bool` | `true` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name for Camunda deployment (e.g., camunda.example.com) | `string` | `""` | no |
| <a name="input_enable_webmodeler"></a> [enable\_webmodeler](#input\_enable\_webmodeler) | Enable Web Modeler component (creates additional client secret) | `bool` | `false` | no |
| <a name="input_resource_prefix"></a> [resource\_prefix](#input\_resource\_prefix) | Prefix for EntraID resources. If empty, uses 'camunda-test' | `string` | `""` | no |
| <a name="input_secret_validity_hours"></a> [secret\_validity\_hours](#input\_secret\_validity\_hours) | Validity period for client secrets in hours (default: 720h = 30 days) | `number` | `720` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for resources | `map(string)` | `{}` | no |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Azure AD Tenant ID (optional, will use current context if not provided) | `string` | `""` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_user_id"></a> [admin\_user\_id](#output\_admin\_user\_id) | Object ID of the created admin user |
| <a name="output_admin_user_principal_name"></a> [admin\_user\_principal\_name](#output\_admin\_user\_principal\_name) | User Principal Name of the created admin user |
| <a name="output_application_id"></a> [application\_id](#output\_application\_id) | Application object ID |
| <a name="output_authorization_url"></a> [authorization\_url](#output\_authorization\_url) | OIDC Authorization endpoint |
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | Application (client) ID for all Camunda components (shared) |
| <a name="output_connectors_client_secret"></a> [connectors\_client\_secret](#output\_connectors\_client\_secret) | Client secret for Connectors |
| <a name="output_created_at"></a> [created\_at](#output\_created\_at) | Timestamp when this EntraID app was created |
| <a name="output_expires_at"></a> [expires\_at](#output\_expires\_at) | Timestamp when this EntraID app should be cleaned up |
| <a name="output_identity_client_secret"></a> [identity\_client\_secret](#output\_identity\_client\_secret) | Client secret for Identity component |
| <a name="output_issuer_url"></a> [issuer\_url](#output\_issuer\_url) | OIDC Issuer URL (Azure AD authority) |
| <a name="output_jwks_url"></a> [jwks\_url](#output\_jwks\_url) | OIDC JWKS endpoint |
| <a name="output_oidc_config"></a> [oidc\_config](#output\_oidc\_config) | Complete OIDC configuration for Camunda |
| <a name="output_optimize_client_secret"></a> [optimize\_client\_secret](#output\_optimize\_client\_secret) | Client secret for Optimize component |
| <a name="output_orchestration_client_secret"></a> [orchestration\_client\_secret](#output\_orchestration\_client\_secret) | Client secret for Orchestration |
| <a name="output_service_principal_id"></a> [service\_principal\_id](#output\_service\_principal\_id) | Service Principal object ID |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Azure AD Tenant ID |
| <a name="output_token_url"></a> [token\_url](#output\_token\_url) | OIDC Token endpoint |
| <a name="output_userinfo_url"></a> [userinfo\_url](#output\_userinfo\_url) | OIDC UserInfo endpoint |
| <a name="output_webmodeler_api_client_secret"></a> [webmodeler\_api\_client\_secret](#output\_webmodeler\_api\_client\_secret) | Client secret for Web Modeler API |
<!-- END_TF_DOCS -->
