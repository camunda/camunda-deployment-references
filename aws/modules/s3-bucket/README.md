# S3 Bucket Module

An encrypted, private S3 bucket with its KMS key and an IAM policy to attach to the ECS task role.

| `purpose` | Use | Versioning |
| --- | --- | --- |
| `backup` | Camunda backups. One per cluster. | on |
| `node-id-lease` | Orchestration Cluster node ID leases on ECS. **One per zone, never shared** between zones or clusters. | off |

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Region of the bucket. The access policy denies S3 calls to other regions. | `string` | n/a | yes |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the bucket. Must be globally unique. | `string` | n/a | yes |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Delete the bucket even if it contains objects. Dev and test only. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Existing KMS key to encrypt the bucket with. When empty, the module creates one. | `string` | `""` | no |
| <a name="input_purpose"></a> [purpose](#input\_purpose) | What the bucket stores. backup: Camunda backups (versioned). node-id-lease: Orchestration Cluster node ID leases (not versioned, one bucket per zone, never shared between zones or clusters). | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_policy_arn"></a> [access\_policy\_arn](#output\_access\_policy\_arn) | ARN of the IAM policy granting read/write access to the bucket and its key; attach it to the ECS task role |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the bucket |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the bucket |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key that encrypts the bucket |
<!-- END_TF_DOCS -->
