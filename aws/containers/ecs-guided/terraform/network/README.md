# Network stage

Creates a VPC, or validates and re-exposes one you bring (`byo_vpc = true`). Wraps [`aws/modules/network`](../../../../modules/network).

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_network"></a> [network](#module\_network) | ../../../../modules/network | n/a |
## Resources

No resources.
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_az_count"></a> [az\_count](#input\_az\_count) | Number of availability zones to use when creating a VPC (at least 3) | `number` | `3` | no |
| <a name="input_byo_vpc"></a> [byo\_vpc](#input\_byo\_vpc) | Use an existing VPC instead of creating one. Requires vpc\_id, vpc\_cidr and private\_subnet\_ids. | `bool` | `false` | no |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | CIDR block of the VPC to create | `string` | `"10.190.0.0/16"` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | BYO: private route table IDs, only needed for peering or transit gateway routes later | `list(string)` | `[]` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | BYO: at least 3 private subnet IDs in distinct availability zones | `list(string)` | `[]` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | BYO: at least 3 public subnet IDs in distinct availability zones, for internet-facing load balancers | `list(string)` | `[]` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Use a single shared NAT gateway instead of one per zone | `bool` | `false` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | BYO: CIDR block of the existing VPC | `string` | `""` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | BYO: ID of the existing VPC | `string` | `""` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | Private route table IDs |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | CIDR block of the VPC |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC |
<!-- END_TF_DOCS -->
