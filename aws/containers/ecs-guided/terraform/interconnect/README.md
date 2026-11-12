# Interconnect

The link between the VPCs of two regions: a peering connection, routes in the private route tables, and Route 53 Resolver rules that forward each region's service discovery domain to the other. Part of [growing to a second region](../../EVOLVE-DUAL.md); it does not change the VPCs.

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
| ---- | ---- |
| [aws_route.a_to_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.b_to_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route53_resolver_endpoint.inbound_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.inbound_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_rule.a_to_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule) | resource |
| [aws_route53_resolver_rule.b_to_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule) | resource |
| [aws_route53_resolver_rule_association.a_to_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule_association) | resource |
| [aws_route53_resolver_rule_association.b_to_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule_association) | resource |
| [aws_security_group.resolver_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.resolver_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_peering_connection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [aws_vpc_peering_connection_accepter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_accepter) | resource |
| [aws_vpc_peering_connection_options.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_options) | resource |
| [aws_vpc_peering_connection_options.requester](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_options) | resource |
| [terraform_data.validate](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_enable_dns_resolver"></a> [enable\_dns\_resolver](#input\_enable\_dns\_resolver) | Forward the service discovery domain of each region to the other through Route 53 Resolver, so that a name registered in one region resolves in the other. | `bool` | `true` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the resources | `string` | n/a | yes |
| <a name="input_private_route_table_ids_a"></a> [private\_route\_table\_ids\_a](#input\_private\_route\_table\_ids\_a) | Network stage output in region\_a: private route table IDs, which get a route to region\_b | `list(string)` | n/a | yes |
| <a name="input_private_route_table_ids_b"></a> [private\_route\_table\_ids\_b](#input\_private\_route\_table\_ids\_b) | Network stage output in region\_b: private route table IDs, which get a route to region\_a | `list(string)` | n/a | yes |
| <a name="input_private_subnet_ids_a"></a> [private\_subnet\_ids\_a](#input\_private\_subnet\_ids\_a) | Network stage output in region\_a: private subnet IDs (the DNS resolver endpoints use two of them) | `list(string)` | n/a | yes |
| <a name="input_private_subnet_ids_b"></a> [private\_subnet\_ids\_b](#input\_private\_subnet\_ids\_b) | Network stage output in region\_b: private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_region_a"></a> [region\_a](#input\_region\_a) | Region of the first deployment (the existing one) | `string` | n/a | yes |
| <a name="input_region_b"></a> [region\_b](#input\_region\_b) | Region of the second deployment | `string` | n/a | yes |
| <a name="input_service_discovery_domain_a"></a> [service\_discovery\_domain\_a](#input\_service\_discovery\_domain\_a) | Service discovery domain of the deployment in region\_a: <prefix of its camunda stage>-oc.service.local. Required with enable\_dns\_resolver. | `string` | `""` | no |
| <a name="input_service_discovery_domain_b"></a> [service\_discovery\_domain\_b](#input\_service\_discovery\_domain\_b) | Service discovery domain of the deployment in region\_b. Required with enable\_dns\_resolver. | `string` | `""` | no |
| <a name="input_vpc_cidr_a"></a> [vpc\_cidr\_a](#input\_vpc\_cidr\_a) | Network stage output in region\_a: VPC CIDR | `string` | n/a | yes |
| <a name="input_vpc_cidr_b"></a> [vpc\_cidr\_b](#input\_vpc\_cidr\_b) | Network stage output in region\_b: VPC CIDR | `string` | n/a | yes |
| <a name="input_vpc_id_a"></a> [vpc\_id\_a](#input\_vpc\_id\_a) | Network stage output in region\_a: VPC ID | `string` | n/a | yes |
| <a name="input_vpc_id_b"></a> [vpc\_id\_b](#input\_vpc\_id\_b) | Network stage output in region\_b: VPC ID | `string` | n/a | yes |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_additional_cidr_blocks_a"></a> [additional\_cidr\_blocks\_a](#output\_additional\_cidr\_blocks\_a) | CIDR to pass as additional\_cidr\_blocks to the compute and storage stages of region\_a, so that the other region reaches them |
| <a name="output_additional_cidr_blocks_b"></a> [additional\_cidr\_blocks\_b](#output\_additional\_cidr\_blocks\_b) | CIDR to pass as additional\_cidr\_blocks to the compute stage of region\_b |
| <a name="output_peering_connection_id"></a> [peering\_connection\_id](#output\_peering\_connection\_id) | ID of the VPC peering connection |
<!-- END_TF_DOCS -->
