# Terraform Setup for EKS dual-region

This folder describes the IaC of Camunda on AWS EKS in a dual-region setup.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/self-managed/deployment/helm/cloud-providers/amazon/amazon-eks/dual-region/

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks_cluster_region_0"></a> [eks\_cluster\_region\_0](#module\_eks\_cluster\_region\_0) | ../../../../modules/eks-cluster | n/a |
| <a name="module_eks_cluster_region_1"></a> [eks\_cluster\_region\_1](#module\_eks\_cluster\_region\_1) | ../../../../modules/eks-cluster | n/a |
## Resources

| Name | Type |
|------|------|
| [aws_iam_access_key.service_account_access_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key) | resource |
| [aws_iam_policy.s3_access_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_user.service_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user) | resource |
| [aws_iam_user_policy_attachment.s3_access_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_kms_alias.s3_bucket_key_alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.s3_bucket_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_route.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.accepter_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.owner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.owner_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_s3_bucket.elastic_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.elastic_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.elastic_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.elastic_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_vpc_peering_connection.owner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [aws_vpc_peering_connection_accepter.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_accepter) | resource |
| [aws_vpc_security_group_ingress_rule.accepter_eks_primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.owner_eks_primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS Profile to use (null = use default credential chain) | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster to prefix resources | `string` | n/a | yes |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version to use | `string` | `"1.35"` | no |
| <a name="input_np_capacity_type"></a> [np\_capacity\_type](#input\_np\_capacity\_type) | Allows setting the capacity type to ON\_DEMAND or SPOT to determine stable nodes | `string` | `"ON_DEMAND"` | no |
| <a name="input_np_desired_node_count"></a> [np\_desired\_node\_count](#input\_np\_desired\_node\_count) | Desired number of nodes in the node pool | `number` | `4` | no |
| <a name="input_np_instance_types"></a> [np\_instance\_types](#input\_np\_instance\_types) | Instance types for the node pool | `list(string)` | <pre>[<br/>  "m6i.xlarge"<br/>]</pre> | no |
| <a name="input_np_max_node_count"></a> [np\_max\_node\_count](#input\_np\_max\_node\_count) | Maximum number of nodes in the node pool | `number` | `10` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | If true, only one NAT gateway will be created to save on e.g. IPs, not good for HA | `bool` | `false` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_s3_aws_access_key"></a> [s3\_aws\_access\_key](#output\_s3\_aws\_access\_key) | n/a |
| <a name="output_s3_aws_secret_access_key"></a> [s3\_aws\_secret\_access\_key](#output\_s3\_aws\_secret\_access\_key) | n/a |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | n/a |
<!-- END_TF_DOCS -->
