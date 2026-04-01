# Camunda 8 on AWS EKS with IRSA

This folder describes the IaC of Camunda 8 on AWS EKS with IRSA.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/self-managed/setup/deploy/amazon/amazon-eks/eks-terraform/

- [AWS Elastic Kubernetes Service](https://aws.amazon.com/eks/)
- [IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks_cluster"></a> [eks\_cluster](#module\_eks\_cluster) | ../../../../modules/eks-cluster | n/a |
| <a name="module_opensearch_domain"></a> [opensearch\_domain](#module\_opensearch\_domain) | ../../../../modules/opensearch | n/a |
| <a name="module_postgresql"></a> [postgresql](#module\_postgresql) | ../../../../modules/aurora | n/a |
## Resources

| Name | Type |
|------|------|
| [random_password.aurora_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.opensearch_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aurora_iam_role_arns"></a> [aurora\_iam\_role\_arns](#output\_aurora\_iam\_role\_arns) | Map of IAM role names to their ARNs |
| <a name="output_aurora_master_password"></a> [aurora\_master\_password](#output\_aurora\_master\_password) | Aurora admin password |
| <a name="output_aurora_master_username"></a> [aurora\_master\_username](#output\_aurora\_master\_username) | Aurora admin username |
| <a name="output_cert_manager_arn"></a> [cert\_manager\_arn](#output\_cert\_manager\_arn) | The Amazon Resource Name (ARN) of the AWS IAM Roles for Service Account mapping for the cert-manager |
| <a name="output_external_dns_arn"></a> [external\_dns\_arn](#output\_external\_dns\_arn) | The Amazon Resource Name (ARN) of the AWS IAM Roles for Service Account mapping for the external-dns |
| <a name="output_opensearch_endpoint"></a> [opensearch\_endpoint](#output\_opensearch\_endpoint) | The OpenSearch endpoint URL |
| <a name="output_opensearch_iam_role_arns"></a> [opensearch\_iam\_role\_arns](#output\_opensearch\_iam\_role\_arns) | Map of IAM role names to their ARNs |
| <a name="output_opensearch_master_password"></a> [opensearch\_master\_password](#output\_opensearch\_master\_password) | OpenSearch admin password |
| <a name="output_postgres_endpoint"></a> [postgres\_endpoint](#output\_postgres\_endpoint) | The Postgres endpoint URL |
| <a name="output_postgres_major_version"></a> [postgres\_major\_version](#output\_postgres\_major\_version) | PostgreSQL major version (derived from Aurora engine\_version) |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the Virtual Private Cloud (VPC) where the cluster and related resources are deployed. |
<!-- END_TF_DOCS -->
