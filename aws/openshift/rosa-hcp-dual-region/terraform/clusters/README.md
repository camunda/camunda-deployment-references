# clusters

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_rosa_cluster_0"></a> [rosa\_cluster\_0](#module\_rosa\_cluster\_0) | ../../../../modules/rosa-hcp | n/a |
| <a name="module_rosa_cluster_1"></a> [rosa\_cluster\_1](#module\_rosa\_cluster\_1) | ../../../../modules/rosa-hcp | n/a |
## Resources

| Name | Type |
|------|------|
| [random_password.rosa_cluster_0_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.rosa_cluster_1_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_0_region"></a> [cluster\_0\_region](#input\_cluster\_0\_region) | Region of the cluster 0 | `string` | `"us-east-1"` | no |
| <a name="input_cluster_1_region"></a> [cluster\_1\_region](#input\_cluster\_1\_region) | Region of the cluster 1 | `string` | `"us-east-2"` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_0_aws_caller_identity_account_id"></a> [cluster\_0\_aws\_caller\_identity\_account\_id](#output\_cluster\_0\_aws\_caller\_identity\_account\_id) | The AWS account ID of the caller. This is the account under which the Terraform code is being executed. |
| <a name="output_cluster_0_cluster_console_url"></a> [cluster\_0\_cluster\_console\_url](#output\_cluster\_0\_cluster\_console\_url) | The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster. |
| <a name="output_cluster_0_cluster_id"></a> [cluster\_0\_cluster\_id](#output\_cluster\_0\_cluster\_id) | The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations. |
| <a name="output_cluster_0_oidc_provider_id"></a> [cluster\_0\_oidc\_provider\_id](#output\_cluster\_0\_oidc\_provider\_id) | OIDC provider for the ROSA cluster. Allows adding additional IAM Role for Service Accounts (IRSA) mappings. |
| <a name="output_cluster_0_openshift_api_url"></a> [cluster\_0\_openshift\_api\_url](#output\_cluster\_0\_openshift\_api\_url) | The endpoint URL for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server. |
| <a name="output_cluster_0_private_subnet_ids"></a> [cluster\_0\_private\_subnet\_ids](#output\_cluster\_0\_private\_subnet\_ids) | A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access. |
| <a name="output_cluster_0_public_subnet_ids"></a> [cluster\_0\_public\_subnet\_ids](#output\_cluster\_0\_public\_subnet\_ids) | A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access. |
| <a name="output_cluster_0_vpc_id"></a> [cluster\_0\_vpc\_id](#output\_cluster\_0\_vpc\_id) | The VPC ID of the cluster. |
| <a name="output_cluster_1_aws_caller_identity_account_id"></a> [cluster\_1\_aws\_caller\_identity\_account\_id](#output\_cluster\_1\_aws\_caller\_identity\_account\_id) | The AWS account ID of the caller. This is the account under which the Terraform code is being executed. |
| <a name="output_cluster_1_cluster_console_url"></a> [cluster\_1\_cluster\_console\_url](#output\_cluster\_1\_cluster\_console\_url) | The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster. |
| <a name="output_cluster_1_cluster_id"></a> [cluster\_1\_cluster\_id](#output\_cluster\_1\_cluster\_id) | The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations. |
| <a name="output_cluster_1_oidc_provider_id"></a> [cluster\_1\_oidc\_provider\_id](#output\_cluster\_1\_oidc\_provider\_id) | OIDC provider for the ROSA cluster. Allows adding additional IAM Role for Service Accounts (IRSA) mappings. |
| <a name="output_cluster_1_openshift_api_url"></a> [cluster\_1\_openshift\_api\_url](#output\_cluster\_1\_openshift\_api\_url) | The endpoint URL for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server. |
| <a name="output_cluster_1_private_subnet_ids"></a> [cluster\_1\_private\_subnet\_ids](#output\_cluster\_1\_private\_subnet\_ids) | A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access. |
| <a name="output_cluster_1_public_subnet_ids"></a> [cluster\_1\_public\_subnet\_ids](#output\_cluster\_1\_public\_subnet\_ids) | A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access. |
| <a name="output_cluster_1_vpc_id"></a> [cluster\_1\_vpc\_id](#output\_cluster\_1\_vpc\_id) | The VPC ID of the cluster. |
| <a name="output_rosa_cluster_0_admin_password"></a> [rosa\_cluster\_0\_admin\_password](#output\_rosa\_cluster\_0\_admin\_password) | ROSA cluster 0 admin password |
| <a name="output_rosa_cluster_1_admin_password"></a> [rosa\_cluster\_1\_admin\_password](#output\_rosa\_cluster\_1\_admin\_password) | ROSA cluster 1 admin password |
<!-- END_TF_DOCS -->
