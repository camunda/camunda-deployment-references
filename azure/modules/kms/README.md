# kms

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_key.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_key) | resource |
| [azurerm_role_assignment.tf_sp_kv_admin](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.tf_sp_kv_crypto_officer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.uami_crypto_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.uami_secrets_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azuread_service_principal.terraform_sp](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_key_expiration_date"></a> [key\_expiration\_date](#input\_key\_expiration\_date) | Expiration date for the Key Vault key | `string` | `"2035-12-31T23:59:59Z"` | no |
| <a name="input_key_name"></a> [key\_name](#input\_key\_name) | Name for the key inside Key Vault | `string` | n/a | yes |
| <a name="input_kv_name"></a> [kv\_name](#input\_kv\_name) | Name for the Key Vault | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the Resource Group to house Key Vault & UAMI | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_terraform_sp_app_id"></a> [terraform\_sp\_app\_id](#input\_terraform\_sp\_app\_id) | The Service Principal’s Application (client) ID that Terraform is using | `string` | n/a | yes |
| <a name="input_uai_name"></a> [uai\_name](#input\_uai\_name) | Name for the User-Assigned Managed Identity | `string` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_key_vault_id"></a> [key\_vault\_id](#output\_key\_vault\_id) | The Key Vault resource ID |
| <a name="output_key_vault_key_id"></a> [key\_vault\_key\_id](#output\_key\_vault\_key\_id) | The specific Key Vault key ID for envelope encryption |
| <a name="output_uami_id"></a> [uami\_id](#output\_uami\_id) | User-Assigned Managed Identity ID |
| <a name="output_uami_object_id"></a> [uami\_object\_id](#output\_uami\_object\_id) | Object ID (GUID) of the User Assigned Managed Identity |
<!-- END_TF_DOCS -->
