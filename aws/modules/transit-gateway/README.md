# transit-gateway

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_transit_gateway.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway) | resource |
| [aws_ec2_transit_gateway.owner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway) | resource |
| [aws_ec2_transit_gateway_peering_attachment.owner_to_accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_peering_attachment) | resource |
| [aws_ec2_transit_gateway_peering_attachment_accepter.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_peering_attachment_accepter) | resource |
| [aws_region.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix for resource names | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_accepter_default_route_table_id"></a> [accepter\_default\_route\_table\_id](#output\_accepter\_default\_route\_table\_id) | Default route table ID of the accepter Transit Gateway |
| <a name="output_accepter_transit_gateway_id"></a> [accepter\_transit\_gateway\_id](#output\_accepter\_transit\_gateway\_id) | ID of the Transit Gateway in the accepter region |
| <a name="output_owner_default_route_table_id"></a> [owner\_default\_route\_table\_id](#output\_owner\_default\_route\_table\_id) | Default route table ID of the owner Transit Gateway |
| <a name="output_owner_transit_gateway_id"></a> [owner\_transit\_gateway\_id](#output\_owner\_transit\_gateway\_id) | ID of the Transit Gateway in the owner region |
| <a name="output_peering_accepter_attachment_id"></a> [peering\_accepter\_attachment\_id](#output\_peering\_accepter\_attachment\_id) | ID of the accepted TGW peering attachment (accepter side) |
| <a name="output_peering_attachment_id"></a> [peering\_attachment\_id](#output\_peering\_attachment\_id) | ID of the TGW peering attachment (owner side) |
<!-- END_TF_DOCS -->
