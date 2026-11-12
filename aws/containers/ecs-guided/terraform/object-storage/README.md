# Object storage stage

One backup bucket per cluster and one node ID lease bucket per zone. The lease relies on S3 conditional writes scoped to the bucket, so a lease bucket is never shared.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_backup"></a> [backup](#module\_backup) | ../../../../modules/s3-bucket | n/a |
| <a name="module_lease"></a> [lease](#module\_lease) | ../../../../modules/s3-bucket | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Region of the buckets | `string` | n/a | yes |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Delete the buckets even if they contain objects. Dev and test only. | `bool` | `false` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the buckets | `string` | n/a | yes |
| <a name="input_zones"></a> [zones](#input\_zones) | Names of the zones of the Orchestration Cluster. One node ID lease bucket is created per zone: a lease bucket is never shared between zones or clusters. | `set(string)` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backup_access_policy_arn"></a> [backup\_access\_policy\_arn](#output\_backup\_access\_policy\_arn) | IAM policy granting access to the backup bucket; attach it to the Orchestration Cluster task role |
| <a name="output_backup_bucket_name"></a> [backup\_bucket\_name](#output\_backup\_bucket\_name) | Name of the backup bucket |
| <a name="output_lease_buckets"></a> [lease\_buckets](#output\_lease\_buckets) | Per zone: the node ID lease bucket and the IAM policy that grants access to it |
<!-- END_TF_DOCS -->
