# transit-gateway-peering

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_transit_gateway_peering_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_peering_attachment) | resource |
| [aws_ec2_transit_gateway_peering_attachment_accepter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_peering_attachment_accepter) | resource |
| [aws_ec2_transit_gateway_route.accepter_to_owner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route.owner_to_accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_region.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_accepter_cidr_blocks"></a> [accepter\_cidr\_blocks](#input\_accepter\_cidr\_blocks) | CIDR blocks reachable through the accepter Transit Gateway | `list(string)` | n/a | yes |
| <a name="input_accepter_transit_gateway_id"></a> [accepter\_transit\_gateway\_id](#input\_accepter\_transit\_gateway\_id) | ID of the Transit Gateway accepting the peering request | `string` | n/a | yes |
| <a name="input_accepter_transit_gateway_route_table_id"></a> [accepter\_transit\_gateway\_route\_table\_id](#input\_accepter\_transit\_gateway\_route\_table\_id) | Route table ID of the accepter Transit Gateway, where routes to the owner CIDRs are installed | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the peering attachment, typically `<cluster_name>-<owner_short_name>-<accepter_short_name>` | `string` | n/a | yes |
| <a name="input_owner_cidr_blocks"></a> [owner\_cidr\_blocks](#input\_owner\_cidr\_blocks) | CIDR blocks reachable through the owner Transit Gateway | `list(string)` | n/a | yes |
| <a name="input_owner_transit_gateway_id"></a> [owner\_transit\_gateway\_id](#input\_owner\_transit\_gateway\_id) | ID of the Transit Gateway initiating the peering request | `string` | n/a | yes |
| <a name="input_owner_transit_gateway_route_table_id"></a> [owner\_transit\_gateway\_route\_table\_id](#input\_owner\_transit\_gateway\_route\_table\_id) | Route table ID of the owner Transit Gateway, where routes to the accepter CIDRs are installed | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_peering_accepter_attachment_id"></a> [peering\_accepter\_attachment\_id](#output\_peering\_accepter\_attachment\_id) | ID of the accepted Transit Gateway peering attachment (accepter side) |
| <a name="output_peering_attachment_id"></a> [peering\_attachment\_id](#output\_peering\_attachment\_id) | ID of the Transit Gateway peering attachment (owner side) |
<!-- END_TF_DOCS -->
