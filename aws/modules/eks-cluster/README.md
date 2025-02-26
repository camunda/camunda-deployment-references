# AWS EKS Cluster Module

Terraform module which creates AWS EKS (Kubernetes) resources with an opinionated configuration targeting Camunda 8.

## Usage

Following is a simple example configuration and should be adjusted as required.

See [inputs](#inputs) for further configuration options and how they affect the cluster creation.

```hcl
module "eks_cluster" {
  source = "github.com/camunda/camunda-tf-eks-module/modules/eks-cluster"

  region             = "eu-central-1"
  name               = "cluster-name"

  cluster_service_ipv4_cidr = "10.190.0.0/16"
  cluster_node_ipv4_cidr    = "10.192.0.0/16"
}
```

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cert_manager_role"></a> [cert\_manager\_role](#module\_cert\_manager\_role) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | 5.52.2 |
| <a name="module_ebs_cs_role"></a> [ebs\_cs\_role](#module\_ebs\_cs\_role) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | 5.52.2 |
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | 20.33.1 |
| <a name="module_external_dns_role"></a> [external\_dns\_role](#module\_external\_dns\_role) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | 5.52.2 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | 5.19.0 |
## Resources

| Name | Type |
|------|------|
| [aws_iam_policy.cert_manager_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ebs_sc_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ebs_sc_access_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.eks_admin_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.external_dns_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_kms_key.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_security_group_rule.cluster_api_to_nodes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [kubernetes_storage_class_v1.ebs_sc](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class_v1) | resource |
| [time_sleep.eks_cluster_warmup](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eips.current_usage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eips) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_servicequotas_service_quota.elastic_ip_quota](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/servicequotas_service_quota) | data source |
| [aws_vpcs.current_vpcs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpcs) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_entries"></a> [access\_entries](#input\_access\_entries) | Map of access entries to add to the cluster. | `any` | `{}` | no |
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | The authentication mode for the cluster. | `string` | `"API"` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | A list of availability zone names in the region. By default, this is set to `null` and is not used; instead, `availability_zones_count` manages the number of availability zones. This value should not be updated directly. To make changes, please create a new resource. | `list(string)` | `null` | no |
| <a name="input_availability_zones_count"></a> [availability\_zones\_count](#input\_availability\_zones\_count) | The count of availability zones to utilize within the specified AWS Region, where pairs of public and private subnets will be generated (minimum is `2`). Valid only when availability\_zones variable is not provided. | `number` | `3` | no |
| <a name="input_cluster_node_ipv4_cidr"></a> [cluster\_node\_ipv4\_cidr](#input\_cluster\_node\_ipv4\_cidr) | The CIDR block for public and private subnets of loadbalancers and nodes. Between /28 and /16. | `string` | `"10.192.0.0/16"` | no |
| <a name="input_cluster_service_ipv4_cidr"></a> [cluster\_service\_ipv4\_cidr](#input\_cluster\_service\_ipv4\_cidr) | The CIDR block to assign Kubernetes service IP addresses from. Between /24 and /12. | `string` | `"10.190.0.0/16"` | no |
| <a name="input_cluster_tags"></a> [cluster\_tags](#input\_cluster\_tags) | A map of additional tags to add to the cluster | `map(string)` | `{}` | no |
| <a name="input_create_ebs_gp3_default_storage_class"></a> [create\_ebs\_gp3\_default\_storage\_class](#input\_create\_ebs\_gp3\_default\_storage\_class) | Flag to determine if the kubernetes\_storage\_class should be created using EBS-CSI and set on GP3 by default. Set to 'false' to skip creating the storage class, useful for avoiding dependency issues during EKS cluster deletion. | `bool` | `true` | no |
| <a name="input_enable_cluster_creator_admin_permissions"></a> [enable\_cluster\_creator\_admin\_permissions](#input\_enable\_cluster\_creator\_admin\_permissions) | Indicates whether or not to add the cluster creator (the identity used by Terraform) as an administrator via access entry. | `bool` | `true` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version to be used by EKS | `string` | `"1.32"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name being used for relevant resources - including EKS cluster name | `string` | n/a | yes |
| <a name="input_np_ami_type"></a> [np\_ami\_type](#input\_np\_ami\_type) | Amazon Machine Image | `string` | `"AL2_x86_64"` | no |
| <a name="input_np_capacity_type"></a> [np\_capacity\_type](#input\_np\_capacity\_type) | Allows setting the capacity type to ON\_DEMAND or SPOT to determine stable nodes | `string` | `"ON_DEMAND"` | no |
| <a name="input_np_desired_node_count"></a> [np\_desired\_node\_count](#input\_np\_desired\_node\_count) | Actual number of nodes for the default node pool. Min-Max will be used for autoscaling | `number` | `4` | no |
| <a name="input_np_disk_size"></a> [np\_disk\_size](#input\_np\_disk\_size) | Disk size of the nodes on the default node pool | `number` | `20` | no |
| <a name="input_np_instance_types"></a> [np\_instance\_types](#input\_np\_instance\_types) | Allow passing a list of instance types for the auto scaler to select from when scaling the default node pool | `list(string)` | <pre>[<br/>  "m6i.xlarge"<br/>]</pre> | no |
| <a name="input_np_labels"></a> [np\_labels](#input\_np\_labels) | A map of labels to add to the default pool nodes | `map(string)` | `{}` | no |
| <a name="input_np_max_node_count"></a> [np\_max\_node\_count](#input\_np\_max\_node\_count) | Maximum number of nodes for the default node pool | `number` | `10` | no |
| <a name="input_np_min_node_count"></a> [np\_min\_node\_count](#input\_np\_min\_node\_count) | Minimum number of nodes for the default node pool | `number` | `1` | no |
| <a name="input_region"></a> [region](#input\_region) | The region where the cluster and relevant resources should be deployed in | `string` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_entries"></a> [access\_entries](#output\_access\_entries) | Map of access entries created and their attributes |
| <a name="output_aws_caller_identity_account_id"></a> [aws\_caller\_identity\_account\_id](#output\_aws\_caller\_identity\_account\_id) | Account ID of the current AWS account |
| <a name="output_cert_manager_arn"></a> [cert\_manager\_arn](#output\_cert\_manager\_arn) | Amazon Resource Name of the cert-manager IAM role used for IAM Roles to Service Accounts mappings |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the cluster |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Endpoint for your Kubernetes API server |
| <a name="output_cluster_iam_role_arn"></a> [cluster\_iam\_role\_arn](#output\_cluster\_iam\_role\_arn) | IAM role ARN of the EKS cluster |
| <a name="output_cluster_iam_role_name"></a> [cluster\_iam\_role\_name](#output\_cluster\_iam\_role\_name) | IAM role name of the EKS cluster |
| <a name="output_cluster_primary_security_group_id"></a> [cluster\_primary\_security\_group\_id](#output\_cluster\_primary\_security\_group\_id) | Cluster primary security group that was created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication. Referred to as 'Cluster security group' in the EKS console |
| <a name="output_cluster_security_group_arn"></a> [cluster\_security\_group\_arn](#output\_cluster\_security\_group\_arn) | Amazon Resource Name (ARN) of the cluster security group |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | Cluster security group that was created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication. Referred to as 'Cluster security group' in the EKS console |
| <a name="output_default_security_group_id"></a> [default\_security\_group\_id](#output\_default\_security\_group\_id) | The ID of the security group created by default on VPC creation |
| <a name="output_ebs_cs_arn"></a> [ebs\_cs\_arn](#output\_ebs\_cs\_arn) | Amazon Resource Name of the ebs-csi IAM role used for IAM Roles to Service Accounts mappings |
| <a name="output_external_dns_arn"></a> [external\_dns\_arn](#output\_external\_dns\_arn) | Amazon Resource Name of the external-dns IAM role used for IAM Roles to Service Accounts mappings |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | Amazon Resource Name of the OIDC provider for the EKS cluster. Allows to add additional IRSA mappings |
| <a name="output_oidc_provider_id"></a> [oidc\_provider\_id](#output\_oidc\_provider\_id) | OIDC provider for the EKS cluster. Allows to add additional IRSA mappings |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | The IDs of the private route tables associated with this VPC |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs |
| <a name="output_private_vpc_cidr_blocks"></a> [private\_vpc\_cidr\_blocks](#output\_private\_vpc\_cidr\_blocks) | Private VPC CIDR blocks |
| <a name="output_public_vpc_cidr_blocks"></a> [public\_vpc\_cidr\_blocks](#output\_public\_vpc\_cidr\_blocks) | Public VPC CIDR blocks |
| <a name="output_vpc_azs"></a> [vpc\_azs](#output\_vpc\_azs) | VPC AZs of the cluster |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC id of the cluster |
| <a name="output_vpc_main_route_table_id"></a> [vpc\_main\_route\_table\_id](#output\_vpc\_main\_route\_table\_id) | The ID of the main route table associated with this VPC |
<!-- END_TF_DOCS -->
