# Camunda 8.7 on AWS EKS

This folder describes the IaC of Camunda 8.7 on AWS EKS.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/self-managed/setup/deploy/amazon/amazon-eks/eks-terraform/

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks_cluster"></a> [eks\_cluster](#module\_eks\_cluster) | git::https://github.com/camunda/camunda-tf-eks-module//modules/eks-cluster | 3.1.3 |
| <a name="module_opensearch_domain"></a> [opensearch\_domain](#module\_opensearch\_domain) | git::https://github.com/camunda/camunda-tf-eks-module//modules/opensearch | 3.1.3 |
| <a name="module_postgresql"></a> [postgresql](#module\_postgresql) | git::https://github.com/camunda/camunda-tf-eks-module//modules/aurora | 3.1.3 |
## Resources

No resources.
## Inputs

No inputs.
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cert_manager_arn"></a> [cert\_manager\_arn](#output\_cert\_manager\_arn) | The Amazon Resource Name (ARN) of the AWS IAM Roles for Service Account mapping for the cert-manager |
| <a name="output_external_dns_arn"></a> [external\_dns\_arn](#output\_external\_dns\_arn) | The Amazon Resource Name (ARN) of the AWS IAM Roles for Service Account mapping for the external-dns |
| <a name="output_opensearch_endpoint"></a> [opensearch\_endpoint](#output\_opensearch\_endpoint) | The OpenSearch endpoint URL |
| <a name="output_postgres_endpoint"></a> [postgres\_endpoint](#output\_postgres\_endpoint) | The Postgres endpoint URL |
<!-- END_TF_DOCS -->
