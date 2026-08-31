# transit-gateway-hub

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_transit_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_route.remote](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the Transit Gateway and its attachment, typically `<cluster_name>-<region_short_name>` | `string` | n/a | yes |
| <a name="input_remote_cidr_blocks"></a> [remote\_cidr\_blocks](#input\_remote\_cidr\_blocks) | CIDR blocks of every remote region VPC that must be reachable through the Transit Gateway | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs used for the Transit Gateway VPC attachment. Use one private subnet per availability zone. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC hosting the regional Kubernetes cluster | `string` | n/a | yes |
| <a name="input_vpc_route_table_ids"></a> [vpc\_route\_table\_ids](#input\_vpc\_route\_table\_ids) | Route table IDs of the local VPC that must be able to reach the remote regions (main + private route tables) | `list(string)` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_transit_gateway_id"></a> [transit\_gateway\_id](#output\_transit\_gateway\_id) | ID of the regional Transit Gateway |
| <a name="output_transit_gateway_route_table_id"></a> [transit\_gateway\_route\_table\_id](#output\_transit\_gateway\_route\_table\_id) | Default association route table ID of the regional Transit Gateway |
| <a name="output_vpc_attachment_id"></a> [vpc\_attachment\_id](#output\_vpc\_attachment\_id) | ID of the VPC attachment of the local cluster VPC |
<!-- END_TF_DOCS -->
