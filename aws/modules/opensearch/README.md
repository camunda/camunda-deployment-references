# AWS OpenSearch Domain Terraform Module

This Terraform module creates and manages an AWS OpenSearch domain. The module is designed to be integrated with an existing EKS cluster or VPC for seamless setup and management. Below is a detailed explanation of the module's configuration options and usage.

## Usage

Below is a simple example configuration that demonstrates how to use this module. Adjust the values as needed for your specific setup.

```hcl
module "opensearch_domain" {
  source = "github.com/camunda/camunda-tf-eks-module/modules/opensearch"

  domain_name     = "my-opensearch-domain"
  engine_version  = "2.15"
  subnet_ids      = module.eks_cluster.private_subnet_ids
  vpc_id          = module.eks_cluster.vpc_id
  cidr_blocks      = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)

  instance_type   = "m7i.large.search"
  instance_count  = 3
  ebs_volume_size = 100

  advanced_security_enabled = true
  advanced_security_internal_user_database_enabled = true
  advanced_security_master_user_name = "admin"
  advanced_security_master_user_password = "password"

  access_policies = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "es:*",
      "Resource": "arn:aws:es:region:account-id:domain/domain-name/*"
    }
  ]
}
EOF
}
```

## Features

- **VPC integration**: Deploy OpenSearch within your existing VPC, ensuring network isolation and better security.
- **Advanced Security Options**: Optional advanced security features, including internal user database and fine-grained access control.
- **EBS Volume Support**: Attach scalable EBS volumes to the OpenSearch data nodes.
- **Zone Awareness**: Deploy the domain across multiple availability zones for better redundancy.
- **Node-to-Node Encryption**: Ensure secure communication between OpenSearch nodes.
- **Cold and Warm Storage**: Support for cold and warm storage tiers for cost-effective long-term data storage.

## Best Practices

- Enable **automated snapshots** to ensure daily backups of your data.
- Use **advanced security options** for production environments to enforce access controls.
- Adjust **instance types** and **EBS volumes** based on the expected workload and data size.

This module integrates seamlessly with existing AWS EKS clusters or standalone VPCs, allowing for flexible configurations of your OpenSearch domain.

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.log_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.log_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_iam_policy.access_policies](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.roles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.attach_policies](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_key.kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_opensearch_domain.opensearch_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/opensearch_domain) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.allow_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.allow_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_iam_policy_document.log_policy_document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_policies"></a> [access\_policies](#input\_access\_policies) | IAM policy document specifying the access policies for the domain. | `string` | `"{}"` | no |
| <a name="input_advanced_options"></a> [advanced\_options](#input\_advanced\_options) | Key-value string pairs to specify advanced configuration options. | `map(any)` | <pre>{<br/>  "rest.action.multi.allow_explicit_index": true<br/>}</pre> | no |
| <a name="input_advanced_security_anonymous_auth_enabled"></a> [advanced\_security\_anonymous\_auth\_enabled](#input\_advanced\_security\_anonymous\_auth\_enabled) | Whether the anonymous auth is enabled. | `bool` | `false` | no |
| <a name="input_advanced_security_enabled"></a> [advanced\_security\_enabled](#input\_advanced\_security\_enabled) | Whether advanced security is enabled. | `bool` | `false` | no |
| <a name="input_advanced_security_internal_user_database_enabled"></a> [advanced\_security\_internal\_user\_database\_enabled](#input\_advanced\_security\_internal\_user\_database\_enabled) | Whether the internal user database is enabled. | `bool` | `false` | no |
| <a name="input_advanced_security_master_user_arn"></a> [advanced\_security\_master\_user\_arn](#input\_advanced\_security\_master\_user\_arn) | ARN for the main user. Only specify if `advanced_security_internal_user_database_enabled` is set to false. | `string` | `""` | no |
| <a name="input_advanced_security_master_user_name"></a> [advanced\_security\_master\_user\_name](#input\_advanced\_security\_master\_user\_name) | Main user's username, which is stored in the Amazon Elasticsearch Service domain's internal database. Only specify if `advanced_security_internal_user_database_enabled` is set to true. | `string` | `"opensearch-admin"` | no |
| <a name="input_advanced_security_master_user_password"></a> [advanced\_security\_master\_user\_password](#input\_advanced\_security\_master\_user\_password) | Main user's password, which is stored in the Amazon Elasticsearch Service domain's internal database. Only specify if `advanced_security_internal_user_database_enabled` is set to true. | `string` | `""` | no |
| <a name="input_auto_software_update_enabled"></a> [auto\_software\_update\_enabled](#input\_auto\_software\_update\_enabled) | Software update auto for the domain. | `bool` | `false` | no |
| <a name="input_auto_tune_options"></a> [auto\_tune\_options](#input\_auto\_tune\_options) | Configuration block for the Auto-Tune options of the domain | `any` | <pre>{<br/>  "desired_state": "DISABLED",<br/>  "rollback_on_disable": "NO_ROLLBACK"<br/>}</pre> | no |
| <a name="input_automated_snapshot_start_hour"></a> [automated\_snapshot\_start\_hour](#input\_automated\_snapshot\_start\_hour) | Hour during which the service takes an automated daily snapshot of the indices in the domain. | `number` | `0` | no |
| <a name="input_cidr_blocks"></a> [cidr\_blocks](#input\_cidr\_blocks) | The CIDR blocks to allow access from and to. | `list(string)` | n/a | yes |
| <a name="input_cold_storage_enabled"></a> [cold\_storage\_enabled](#input\_cold\_storage\_enabled) | Indicates cold storage is enabled. | `bool` | `false` | no |
| <a name="input_create_timeout"></a> [create\_timeout](#input\_create\_timeout) | How much time to wait for the creation before timing out. | `string` | `"2h"` | no |
| <a name="input_dedicated_master_count"></a> [dedicated\_master\_count](#input\_dedicated\_master\_count) | Number of dedicated master nodes in the cluster. | `number` | `3` | no |
| <a name="input_dedicated_master_enabled"></a> [dedicated\_master\_enabled](#input\_dedicated\_master\_enabled) | Indicates whether dedicated master nodes are enabled for the cluster. | `bool` | `true` | no |
| <a name="input_dedicated_master_type"></a> [dedicated\_master\_type](#input\_dedicated\_master\_type) | Instance type of the dedicated master nodes in the cluster. | `string` | `"m5.large.search"` | no |
| <a name="input_domain_endpoint_options"></a> [domain\_endpoint\_options](#input\_domain\_endpoint\_options) | Configuration block for domain endpoint HTTP(S) related options | `any` | <pre>{<br/>  "enforce_https": true,<br/>  "tls_security_policy": "Policy-Min-TLS-1-2-2019-07"<br/>}</pre> | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Name of the domain. | `string` | n/a | yes |
| <a name="input_ebs_enabled"></a> [ebs\_enabled](#input\_ebs\_enabled) | Whether EBS volumes are attached to data nodes in the domain. | `bool` | `true` | no |
| <a name="input_ebs_iops"></a> [ebs\_iops](#input\_ebs\_iops) | Baseline input/output (I/O) performance of EBS volumes attached to data nodes. Applicable only for the GP3 and Provisioned IOPS EBS volume types. | `number` | `3000` | no |
| <a name="input_ebs_throughput"></a> [ebs\_throughput](#input\_ebs\_throughput) | (Required if `ebs_volume_type` is set to gp3) Specifies the throughput (in MiB/s) of the EBS volumes attached to data nodes. Applicable only for the gp3 volume type. | `number` | `125` | no |
| <a name="input_ebs_volume_size"></a> [ebs\_volume\_size](#input\_ebs\_volume\_size) | Size of EBS volumes attached to data nodes. | `number` | `64` | no |
| <a name="input_ebs_volume_type"></a> [ebs\_volume\_type](#input\_ebs\_volume\_type) | Type of EBS volumes attached to data nodes. | `string` | `"gp3"` | no |
| <a name="input_enable_access_policy"></a> [enable\_access\_policy](#input\_enable\_access\_policy) | Determines whether an access policy will be applied to the domain | `bool` | `true` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | OpenSearch version for the domain. | `string` | `"2.15"` | no |
| <a name="input_iam_roles_with_policies"></a> [iam\_roles\_with\_policies](#input\_iam\_roles\_with\_policies) | List of roles with their trust and access policies | <pre>list(object({<br/>    # Name of the Role to create<br/>    role_name = string<br/><br/>    # Assume role trust policy for this Aurora role as a json string<br/>    trust_policy = string<br/><br/>    # Access policy for Aurora allowing access as a json string<br/>    # see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html<br/>    # Example:<br/>    #   [<br/>    #     {<br/>    #     role_name      = "OpenSearchRole"<br/>    #     trust_policy   =<br/>    # {<br/>    #   "Version": "2012-10-17",<br/>    #   "Statement": [<br/>    #     {<br/>    #       "Effect": "Allow",<br/>    #       "Principal": {<br/>    #         "Federated": "arn:aws:iam::<YOUR-ACCOUNT-ID>:oidc-provider/oidc.eks.<YOUR-REGION>.amazonaws.com/id/<YOUR-OIDC-ID>"<br/>    #       },<br/>    #       "Action": "sts:AssumeRoleWithWebIdentity",<br/>    #       "Condition": {<br/>    #         "StringEquals": {<br/>    #           "oidc.eks.<YOUR-REGION>.amazonaws.com/id/<YOUR-OIDC-PROVIDER-ID>:sub": "system:serviceaccount:<YOUR-NAMESPACE>:<YOUR-SA-NAME>"<br/>    #         }<br/>    #       }<br/>    #     }<br/>    #   ]<br/>    # }<br/>    #<br/>    #     access_policy  =<br/>    # {<br/>    #   "Version": "2012-10-17",<br/>    #   "Statement": [<br/>    #     {<br/>    #       "Effect": "Allow",<br/>    #       "Action": [<br/>    #         "es:DescribeElasticsearchDomains",<br/>    #         "es:DescribeElasticsearchInstanceTypeLimits",<br/>    #         "es:DescribeReservedElasticsearchInstanceOfferings",<br/>    #         "es:DescribeReservedElasticsearchInstances",<br/>    #         "es:GetCompatibleElasticsearchVersions",<br/>    #         "es:ListDomainNames",<br/>    #         "es:ListElasticsearchInstanceTypes",<br/>    #         "es:ListElasticsearchVersions",<br/>    #         "es:DescribeElasticsearchDomain",<br/>    #         "es:DescribeElasticsearchDomainConfig",<br/>    #         "es:ESHttpGet",<br/>    #         "es:ESHttpHead",<br/>    #         "es:GetUpgradeHistory",<br/>    #         "es:GetUpgradeStatus",<br/>    #         "es:ListTags",<br/>    #         "es:AddTags",<br/>    #         "es:RemoveTags",<br/>    #         "es:ESHttpDelete",<br/>    #         "es:ESHttpPost",<br/>    #         "es:ESHttpPut"<br/>    #       ],<br/>    #       "Resource": "arn:aws:es:<YOUR-REGION>:<YOUR-ACCOUNT-ID>:domain/<YOUR-DOMAIN-NAME>/*"<br/>    #     }<br/>    #   ]<br/>    # }<br/>    #<br/>    #   }<br/>    #   ]<br/>    access_policy = string<br/>  }))</pre> | `[]` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of instances in the cluster. | `number` | `3` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Instance type of data nodes in the cluster. | `string` | `"t3.small.search"` | no |
| <a name="input_ip_address_type"></a> [ip\_address\_type](#input\_ip\_address\_type) | The IP address type for the endpoint. Valid values are ipv4 and dualstack | `string` | `"ipv4"` | no |
| <a name="input_kms_key_delete_window_in_days"></a> [kms\_key\_delete\_window\_in\_days](#input\_kms\_key\_delete\_window\_in\_days) | The number of days before the KMS key is deleted after being disabled. | `number` | `7` | no |
| <a name="input_kms_key_enable_key_rotation"></a> [kms\_key\_enable\_key\_rotation](#input\_kms\_key\_enable\_key\_rotation) | Specifies whether automatic key rotation is enabled for the KMS key. | `bool` | `true` | no |
| <a name="input_kms_key_tags"></a> [kms\_key\_tags](#input\_kms\_key\_tags) | The tags to associate with the KMS key. | `map(string)` | `{}` | no |
| <a name="input_log_types"></a> [log\_types](#input\_log\_types) | The types of logs to publish to CloudWatch Logs. Example: [SEARCH\_SLOW\_LOGS, INDEX\_SLOW\_LOGS, ES\_APPLICATION\_LOGS] | `list(string)` | `[]` | no |
| <a name="input_multi_az_with_standby_enabled"></a> [multi\_az\_with\_standby\_enabled](#input\_multi\_az\_with\_standby\_enabled) | Whether a multi-AZ domain is turned on with a standby AZ. | `bool` | `false` | no |
| <a name="input_node_to_node_encryption_enabled"></a> [node\_to\_node\_encryption\_enabled](#input\_node\_to\_node\_encryption\_enabled) | Whether node to node encryption is enabled. | `bool` | `true` | no |
| <a name="input_off_peak_window_enabled"></a> [off\_peak\_window\_enabled](#input\_off\_peak\_window\_enabled) | Whether to enable off peak update | `bool` | `true` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Additional security groups used by the domain. | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The subnet IDs to create the cluster in. For easier usage we are passing through the subnet IDs from the AWS EKS Cluster module. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags assigned to the domain. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC used by the domain. | `string` | n/a | yes |
| <a name="input_warm_count"></a> [warm\_count](#input\_warm\_count) | Number of warm nodes in the cluster. | `number` | `2` | no |
| <a name="input_warm_enabled"></a> [warm\_enabled](#input\_warm\_enabled) | Warm storage is enabled. | `bool` | `false` | no |
| <a name="input_warm_type"></a> [warm\_type](#input\_warm\_type) | Instance type for the OpenSearch cluster's warm nodes. | `string` | `"ultrawarm1.medium.search"` | no |
| <a name="input_zone_awareness_availability_zone_count"></a> [zone\_awareness\_availability\_zone\_count](#input\_zone\_awareness\_availability\_zone\_count) | Number of availability zones used. | `number` | `3` | no |
| <a name="input_zone_awareness_enabled"></a> [zone\_awareness\_enabled](#input\_zone\_awareness\_enabled) | Indicates whether zone awareness is enabled. | `bool` | `true` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | The ARN of the KMS key used to encrypt the OpenSearch domain |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | The ID of the KMS key used for OpenSearch domain encryption |
| <a name="output_opensearch_cluster"></a> [opensearch\_cluster](#output\_opensearch\_cluster) | OpenSearch cluster output |
| <a name="output_opensearch_domain_arn"></a> [opensearch\_domain\_arn](#output\_opensearch\_domain\_arn) | The ARN of the OpenSearch domain |
| <a name="output_opensearch_domain_endpoint"></a> [opensearch\_domain\_endpoint](#output\_opensearch\_domain\_endpoint) | The endpoint of the OpenSearch domain |
| <a name="output_opensearch_domain_id"></a> [opensearch\_domain\_id](#output\_opensearch\_domain\_id) | The ID of the OpenSearch domain |
| <a name="output_opensearch_iam_role_access_policy_arns"></a> [opensearch\_iam\_role\_access\_policy\_arns](#output\_opensearch\_iam\_role\_access\_policy\_arns) | Map of IAM role names to their access policy ARNs |
| <a name="output_opensearch_iam_role_arns"></a> [opensearch\_iam\_role\_arns](#output\_opensearch\_iam\_role\_arns) | Map of IAM role names to their ARNs |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | The ID of the security group used by OpenSearch |
| <a name="output_security_group_rule_egress"></a> [security\_group\_rule\_egress](#output\_security\_group\_rule\_egress) | Egress rule information for OpenSearch security group |
| <a name="output_security_group_rule_ingress"></a> [security\_group\_rule\_ingress](#output\_security\_group\_rule\_ingress) | Ingress rule information for OpenSearch security group |
<!-- END_TF_DOCS -->
