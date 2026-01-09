# Camunda 8 on AWS EKS

This folder describes the IaC of Camunda 8 on AWS EKS.
Instructions can be found on the official documentation: https://docs.camunda.io/docs/self-managed/setup/deploy/amazon/amazon-eks/eks-terraform/

- [AWS Elastic Kubernetes Service](https://aws.amazon.com/eks/)

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
| [aws_cognito_resource_server.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_resource_server) | resource |
| [aws_cognito_user.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user) | resource |
| [aws_cognito_user_pool.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool) | resource |
| [aws_cognito_user_pool_client.connectors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.console](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.identity](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.optimize](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.orchestration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.webmodeler_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_client.webmodeler_ui](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_domain.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_domain) | resource |
| [aws_iam_policy.cognito_secrets_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_secretsmanager_secret.cognito](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.cognito](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cognito_admin_temporary_password"></a> [cognito\_admin\_temporary\_password](#input\_cognito\_admin\_temporary\_password) | Temporary password for the initial admin user (must be changed on first login) | `string` | `"TempP@ssw0rd123!"` | no |
| <a name="input_cognito_create_admin_user"></a> [cognito\_create\_admin\_user](#input\_cognito\_create\_admin\_user) | Create an initial admin user in Cognito | `bool` | `true` | no |
| <a name="input_cognito_mfa_enabled"></a> [cognito\_mfa\_enabled](#input\_cognito\_mfa\_enabled) | Enable MFA for Cognito users (OPTIONAL mode) | `bool` | `false` | no |
| <a name="input_cognito_resource_prefix"></a> [cognito\_resource\_prefix](#input\_cognito\_resource\_prefix) | Prefix for Cognito resource names. If empty, uses the EKS cluster name | `string` | `""` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name for Camunda deployment (e.g., camunda.example.com) | `string` | `""` | no |
| <a name="input_enable_cognito"></a> [enable\_cognito](#input\_enable\_cognito) | Enable Amazon Cognito as the identity provider instead of Keycloak | `bool` | `false` | no |
| <a name="input_enable_console"></a> [enable\_console](#input\_enable\_console) | Enable Camunda Console component | `bool` | `false` | no |
| <a name="input_enable_webmodeler"></a> [enable\_webmodeler](#input\_enable\_webmodeler) | Enable Web Modeler component | `bool` | `false` | no |
| <a name="input_identity_initial_user_email"></a> [identity\_initial\_user\_email](#input\_identity\_initial\_user\_email) | Email address for the initial admin user | `string` | `"admin@camunda.local"` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_camunda_domain_name"></a> [camunda\_domain\_name](#output\_camunda\_domain\_name) | Domain name for Camunda deployment |
| <a name="output_cert_manager_arn"></a> [cert\_manager\_arn](#output\_cert\_manager\_arn) | The Amazon Resource Name (ARN) of the AWS IAM Roles for Service Account mapping for the cert-manager |
| <a name="output_cognito_authorization_url"></a> [cognito\_authorization\_url](#output\_cognito\_authorization\_url) | Cognito Authorization URL |
| <a name="output_cognito_domain"></a> [cognito\_domain](#output\_cognito\_domain) | Cognito User Pool domain |
| <a name="output_cognito_enabled"></a> [cognito\_enabled](#output\_cognito\_enabled) | Whether Cognito authentication is enabled |
| <a name="output_cognito_issuer_url"></a> [cognito\_issuer\_url](#output\_cognito\_issuer\_url) | Cognito OIDC Issuer URL |
| <a name="output_cognito_jwks_url"></a> [cognito\_jwks\_url](#output\_cognito\_jwks\_url) | Cognito JWKS URL |
| <a name="output_cognito_secret_arn"></a> [cognito\_secret\_arn](#output\_cognito\_secret\_arn) | ARN of the AWS Secrets Manager secret containing Cognito credentials |
| <a name="output_cognito_secret_name"></a> [cognito\_secret\_name](#output\_cognito\_secret\_name) | Name of the AWS Secrets Manager secret containing Cognito credentials |
| <a name="output_cognito_secrets_access_policy_arn"></a> [cognito\_secrets\_access\_policy\_arn](#output\_cognito\_secrets\_access\_policy\_arn) | ARN of the IAM policy for accessing Cognito secrets |
| <a name="output_cognito_token_url"></a> [cognito\_token\_url](#output\_cognito\_token\_url) | Cognito Token URL |
| <a name="output_cognito_user_pool_arn"></a> [cognito\_user\_pool\_arn](#output\_cognito\_user\_pool\_arn) | Cognito User Pool ARN |
| <a name="output_cognito_user_pool_endpoint"></a> [cognito\_user\_pool\_endpoint](#output\_cognito\_user\_pool\_endpoint) | Cognito User Pool endpoint |
| <a name="output_cognito_user_pool_id"></a> [cognito\_user\_pool\_id](#output\_cognito\_user\_pool\_id) | Cognito User Pool ID |
| <a name="output_connectors_client_id"></a> [connectors\_client\_id](#output\_connectors\_client\_id) | Connectors App Client ID |
| <a name="output_connectors_client_secret"></a> [connectors\_client\_secret](#output\_connectors\_client\_secret) | Connectors App Client Secret |
| <a name="output_console_client_id"></a> [console\_client\_id](#output\_console\_client\_id) | Console App Client ID |
| <a name="output_external_dns_arn"></a> [external\_dns\_arn](#output\_external\_dns\_arn) | The Amazon Resource Name (ARN) of the AWS IAM Roles for Service Account mapping for the external-dns |
| <a name="output_identity_client_id"></a> [identity\_client\_id](#output\_identity\_client\_id) | Identity App Client ID |
| <a name="output_identity_client_secret"></a> [identity\_client\_secret](#output\_identity\_client\_secret) | Identity App Client Secret |
| <a name="output_identity_initial_user_email"></a> [identity\_initial\_user\_email](#output\_identity\_initial\_user\_email) | Email of the initial admin user |
| <a name="output_opensearch_endpoint"></a> [opensearch\_endpoint](#output\_opensearch\_endpoint) | The OpenSearch endpoint URL |
| <a name="output_optimize_client_id"></a> [optimize\_client\_id](#output\_optimize\_client\_id) | Optimize App Client ID |
| <a name="output_optimize_client_secret"></a> [optimize\_client\_secret](#output\_optimize\_client\_secret) | Optimize App Client Secret |
| <a name="output_orchestration_client_id"></a> [orchestration\_client\_id](#output\_orchestration\_client\_id) | Orchestration App Client ID |
| <a name="output_orchestration_client_secret"></a> [orchestration\_client\_secret](#output\_orchestration\_client\_secret) | Orchestration App Client Secret |
| <a name="output_postgres_endpoint"></a> [postgres\_endpoint](#output\_postgres\_endpoint) | The Postgres endpoint URL |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the Virtual Private Cloud (VPC) where the cluster and related resources are deployed. |
| <a name="output_webmodeler_api_client_id"></a> [webmodeler\_api\_client\_id](#output\_webmodeler\_api\_client\_id) | WebModeler API App Client ID |
| <a name="output_webmodeler_api_client_secret"></a> [webmodeler\_api\_client\_secret](#output\_webmodeler\_api\_client\_secret) | WebModeler API App Client Secret |
| <a name="output_webmodeler_ui_client_id"></a> [webmodeler\_ui\_client\_id](#output\_webmodeler\_ui\_client\_id) | WebModeler UI App Client ID |
<!-- END_TF_DOCS -->
