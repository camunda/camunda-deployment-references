# vpn

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_vpn"></a> [vpn](#module\_vpn) | ../../../../modules/vpn | n/a |
## Resources

| Name | Type |
|------|------|
| [aws_subnets.private_subnets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_s3_bucket_region"></a> [s3\_bucket\_region](#input\_s3\_bucket\_region) | Region of the bucket | `string` | `"eu-central-1"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The ID of the VPC where the VPN will be created | `string` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_vpn_client_configs_s3_urls"></a> [vpn\_client\_configs\_s3\_urls](#output\_vpn\_client\_configs\_s3\_urls) | Map of S3 URLs of each VPN client config (client's name is the key) |
| <a name="output_vpn_endpoint"></a> [vpn\_endpoint](#output\_vpn\_endpoint) | Endpoint of the VPN |
<!-- END_TF_DOCS -->
