# terraform

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_rosa_cluster_1"></a> [rosa\_cluster\_1](#module\_rosa\_cluster\_1) | git::https://github.com/camunda/camunda-tf-rosa//modules/rosa-hcp | v2.0.0 |
| <a name="module_rosa_cluster_2"></a> [rosa\_cluster\_2](#module\_rosa\_cluster\_2) | git::https://github.com/camunda/camunda-tf-rosa//modules/rosa-hcp | v2.0.0 |
## Resources

| Name | Type |
|------|------|
| [aws_iam_access_key.service_account_access_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key) | resource |
| [aws_iam_policy.s3_access_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_user.service_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user) | resource |
| [aws_iam_user_policy_attachment.s3_access_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_kms_key.backup_bucket_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_route.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.cluster_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.cluster_1_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.cluster_2_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_s3_bucket.elastic_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.log_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_acl.log_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_public_access_block.block_public_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.block_public_policy_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.encrypt_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.encrypt_log_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.versionning_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.versionning_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_vpc_peering_connection.cluster_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [aws_vpc_peering_connection_accepter.cluster_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_accepter) | resource |
| [aws_vpc_peering_connection_options.cluster_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_options) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_1_primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_2_primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_region.cluster_1_region](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_region.cluster_2_region](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_bucket_region"></a> [backup\_bucket\_region](#input\_backup\_bucket\_region) | Region of the backup bucket | `string` | `"us-east-1"` | no |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the bucket used to backup the platform | `string` | `"camunda-elastic-backup-rosa-dual"` | no |
| <a name="input_cluster_1_region"></a> [cluster\_1\_region](#input\_cluster\_1\_region) | Region of the cluster 1 | `string` | `"us-east-1"` | no |
| <a name="input_cluster_2_region"></a> [cluster\_2\_region](#input\_cluster\_2\_region) | Region of the cluster 2 | `string` | `"us-east-2"` | no |
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
| <a name="output_s3_aws_access_key"></a> [s3\_aws\_access\_key](#output\_s3\_aws\_access\_key) | n/a |
| <a name="output_s3_aws_secret_access_key"></a> [s3\_aws\_secret\_access\_key](#output\_s3\_aws\_secret\_access\_key) | n/a |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | n/a |
<!-- END_TF_DOCS -->
