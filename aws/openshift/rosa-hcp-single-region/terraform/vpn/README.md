# vpn

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_vpn"></a> [vpn](#module\_vpn) | ../../../../modules/vpn | n/a |
## Resources

No resources.
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_s3_bucket_region"></a> [s3\_bucket\_region](#input\_s3\_bucket\_region) | Region of the bucket | `string` | `"eu-central-1"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The ID of the VPC where the VPN will be created | `string` | n/a | yes |
| <a name="input_vpc_subnet_ids"></a> [vpc\_subnet\_ids](#input\_vpc\_subnet\_ids) | List of subnet IDs in the VPC to attach the VPN | `list(string)` | n/a | yes |
| <a name="input_vpc_target_network_cidr"></a> [vpc\_target\_network\_cidr](#input\_vpc\_target\_network\_cidr) | CIDR block of the target network within the VPC | `string` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_vpn_client_configs_s3_urls"></a> [vpn\_client\_configs\_s3\_urls](#output\_vpn\_client\_configs\_s3\_urls) | Map of S3 URLs of each VPN client config (client's name is the key) |
| <a name="output_vpn_endpoint"></a> [vpn\_endpoint](#output\_vpn\_endpoint) | Endpoint of the VPN |
<!-- END_TF_DOCS -->
