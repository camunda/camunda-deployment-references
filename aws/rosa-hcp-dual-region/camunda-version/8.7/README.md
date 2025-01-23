# 8.7

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_rosa_cluster_1"></a> [rosa\_cluster\_1](#module\_rosa\_cluster\_1) | git::https://github.com/camunda/camunda-tf-rosa//modules/rosa-hcp | v2.0.0 |
| <a name="module_rosa_cluster_2"></a> [rosa\_cluster\_2](#module\_rosa\_cluster\_2) | git::https://github.com/camunda/camunda-tf-rosa//modules/rosa-hcp | v2.0.0 |
## Resources

No resources.
## Inputs

No inputs.
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_1_aws_caller_identity_account_id"></a> [cluster\_1\_aws\_caller\_identity\_account\_id](#output\_cluster\_1\_aws\_caller\_identity\_account\_id) | The AWS account ID of the caller. This is the account under which the Terraform code is being executed. |
| <a name="output_cluster_1_cluster_console_url"></a> [cluster\_1\_cluster\_console\_url](#output\_cluster\_1\_cluster\_console\_url) | The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster. |
| <a name="output_cluster_1_cluster_id"></a> [cluster\_1\_cluster\_id](#output\_cluster\_1\_cluster\_id) | The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations. |
| <a name="output_cluster_1_oidc_provider_id"></a> [cluster\_1\_oidc\_provider\_id](#output\_cluster\_1\_oidc\_provider\_id) | OIDC provider for the ROSA cluster. Allows adding additional IAM Role for Service Accounts (IRSA) mappings. |
| <a name="output_cluster_1_openshift_api_url"></a> [cluster\_1\_openshift\_api\_url](#output\_cluster\_1\_openshift\_api\_url) | The endpoint URL for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server. |
| <a name="output_cluster_1_private_subnet_ids"></a> [cluster\_1\_private\_subnet\_ids](#output\_cluster\_1\_private\_subnet\_ids) | A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access. |
| <a name="output_cluster_1_public_subnet_ids"></a> [cluster\_1\_public\_subnet\_ids](#output\_cluster\_1\_public\_subnet\_ids) | A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access. |
| <a name="output_cluster_2_aws_caller_identity_account_id"></a> [cluster\_2\_aws\_caller\_identity\_account\_id](#output\_cluster\_2\_aws\_caller\_identity\_account\_id) | The AWS account ID of the caller. This is the account under which the Terraform code is being executed. |
| <a name="output_cluster_2_cluster_console_url"></a> [cluster\_2\_cluster\_console\_url](#output\_cluster\_2\_cluster\_console\_url) | The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster. |
| <a name="output_cluster_2_cluster_id"></a> [cluster\_2\_cluster\_id](#output\_cluster\_2\_cluster\_id) | The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations. |
| <a name="output_cluster_2_oidc_provider_id"></a> [cluster\_2\_oidc\_provider\_id](#output\_cluster\_2\_oidc\_provider\_id) | OIDC provider for the ROSA cluster. Allows adding additional IAM Role for Service Accounts (IRSA) mappings. |
| <a name="output_cluster_2_openshift_api_url"></a> [cluster\_2\_openshift\_api\_url](#output\_cluster\_2\_openshift\_api\_url) | The endpoint URL for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server. |
| <a name="output_cluster_2_private_subnet_ids"></a> [cluster\_2\_private\_subnet\_ids](#output\_cluster\_2\_private\_subnet\_ids) | A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access. |
| <a name="output_cluster_2_public_subnet_ids"></a> [cluster\_2\_public\_subnet\_ids](#output\_cluster\_2\_public\_subnet\_ids) | A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access. |
<!-- END_TF_DOCS -->
