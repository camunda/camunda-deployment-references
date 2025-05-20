# Camunda on AWS ROSA single-region

This folder describes the IaC of Camunda on AWS ROSA in a single-region setup.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/8.7/self-managed/setup/deploy/amazon/openshift/terraform-setup/

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_rosa_cluster"></a> [rosa\_cluster](#module\_rosa\_cluster) | ../../modules/rosa-hcp | n/a |
| <a name="module_vpn"></a> [vpn](#module\_vpn) | ../../modules/vpn | n/a |
## Resources

No resources.
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_s3_bucket_region"></a> [s3\_bucket\_region](#input\_s3\_bucket\_region) | Region of the bucket | `string` | `"eu-central-1"` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_caller_identity_account_id"></a> [aws\_caller\_identity\_account\_id](#output\_aws\_caller\_identity\_account\_id) | The AWS account ID of the caller. This is the account under which the Terraform code is being executed. |
| <a name="output_cluster_console_url"></a> [cluster\_console\_url](#output\_cluster\_console\_url) | The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations. |
| <a name="output_oidc_provider_id"></a> [oidc\_provider\_id](#output\_oidc\_provider\_id) | OIDC provider for the ROSA cluster. Allows adding additional IAM Role for Service Accounts (IRSA) mappings. |
| <a name="output_openshift_api_url"></a> [openshift\_api\_url](#output\_openshift\_api\_url) | The endpoint URL for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access. |
| <a name="output_vpn_client_keys_s3_urls"></a> [vpn\_client\_keys\_s3\_urls](#output\_vpn\_client\_keys\_s3\_urls) | Map of S3 URLs for client private and public keys |
| <a name="output_vpn_endpoint"></a> [vpn\_endpoint](#output\_vpn\_endpoint) | Endpoint of the VPN |
<!-- END_TF_DOCS -->
