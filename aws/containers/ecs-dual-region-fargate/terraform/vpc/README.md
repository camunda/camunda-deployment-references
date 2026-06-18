# vpc

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_transit_gateway"></a> [transit\_gateway](#module\_transit\_gateway) | ../../../../modules/transit-gateway | n/a |
| <a name="module_vpc_region_0"></a> [vpc\_region\_0](#module\_vpc\_region\_0) | terraform-aws-modules/vpc/aws | v6.6.1 |
| <a name="module_vpc_region_1"></a> [vpc\_region\_1](#module\_vpc\_region\_1) | terraform-aws-modules/vpc/aws | v6.6.1 |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_transit_gateway_route.region_0_to_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route.region_1_to_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_route.region_0_private_to_region_1_peering](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.region_0_private_to_region_1_tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.region_1_private_to_region_0_peering](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.region_1_private_to_region_0_tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route53_resolver_endpoint.inbound_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.inbound_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_rule.region_0_to_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule) | resource |
| [aws_route53_resolver_rule.region_1_to_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule) | resource |
| [aws_route53_resolver_rule_association.region_0_to_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule_association) | resource |
| [aws_route53_resolver_rule_association.region_1_to_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule_association) | resource |
| [aws_security_group.dns_resolver_region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.dns_resolver_region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_peering_connection.cross_region](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [aws_vpc_peering_connection_accepter.cross_region](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_accepter) | resource |
| [aws_vpc_peering_connection_options.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_options) | resource |
| [aws_vpc_peering_connection_options.requester](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_options) | resource |
| [aws_availability_zones.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_availability_zones.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS Profile to use (null = use default credential chain) | `string` | `null` | no |
| <a name="input_byo_vpc"></a> [byo\_vpc](#input\_byo\_vpc) | If true, this state consumes existing VPCs from the region\_{0,1}\_vpc\_id<br/>variables (and friends) and only creates cross-region peering/TGW plus<br/>optional Route 53 Resolver endpoints. If false (default), Terraform<br/>creates two VPCs from scratch using terraform-aws-modules/vpc/aws.<br/><br/>When true: region\_{0,1}\_vpc\_id, region\_{0,1}\_vpc\_cidr, and at least 3<br/>private + 3 database subnet IDs per region MUST be supplied. Validation<br/>is enforced by check blocks at plan time. | `bool` | `false` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster to prefix resources (used for created resources only — BYO resources keep their existing names) | `string` | n/a | yes |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all created resources | `map(string)` | `{}` | no |
| <a name="input_enable_cross_region_dns_resolver"></a> [enable\_cross\_region\_dns\_resolver](#input\_enable\_cross\_region\_dns\_resolver) | Create Route 53 Resolver endpoints and forwarding rules for cross-region Cloud Map DNS.<br/>Requires the IAM permission route53resolver:CreateResolverEndpoint on the calling principal.<br/>Zeebe Raft and Connectors work without this because cross-region contact uses NLB DNS names.<br/>Enable once the permission is granted if you need cross-region Service Connect name resolution. | `bool` | `false` | no |
| <a name="input_networking_mode"></a> [networking\_mode](#input\_networking\_mode) | Cross-region networking: 'transit\_gateway' or 'vpc\_peering' | `string` | `"transit_gateway"` | no |
| <a name="input_region_0"></a> [region\_0](#input\_region\_0) | AWS region for the primary (owner) cluster | `string` | `"eu-west-2"` | no |
| <a name="input_region_0_cidr"></a> [region\_0\_cidr](#input\_region\_0\_cidr) | VPC CIDR block to create for region 0 (only used when byo\_vpc = false) | `string` | `"10.192.0.0/16"` | no |
| <a name="input_region_0_private_route_table_ids"></a> [region\_0\_private\_route\_table\_ids](#input\_region\_0\_private\_route\_table\_ids) | Route table IDs associated with region 0 private subnets. Peering/TGW routes are added to these. Required when byo\_vpc = true. | `list(string)` | `[]` | no |
| <a name="input_region_0_private_subnet_ids"></a> [region\_0\_private\_subnet\_ids](#input\_region\_0\_private\_subnet\_ids) | Existing private subnet IDs in region 0 (≥3 across distinct AZs, required when byo\_vpc = true) | `list(string)` | `[]` | no |
| <a name="input_region_0_public_subnet_ids"></a> [region\_0\_public\_subnet\_ids](#input\_region\_0\_public\_subnet\_ids) | Existing public subnet IDs in region 0 (≥3 across distinct AZs, used for ALBs; required when byo\_vpc = true) | `list(string)` | `[]` | no |
| <a name="input_region_0_vpc_cidr"></a> [region\_0\_vpc\_cidr](#input\_region\_0\_vpc\_cidr) | CIDR block of the existing VPC in region 0 (required when byo\_vpc = true) | `string` | `""` | no |
| <a name="input_region_0_vpc_id"></a> [region\_0\_vpc\_id](#input\_region\_0\_vpc\_id) | Existing VPC ID in region 0 (required when byo\_vpc = true) | `string` | `""` | no |
| <a name="input_region_1"></a> [region\_1](#input\_region\_1) | AWS region for the secondary (accepter) cluster | `string` | `"eu-west-3"` | no |
| <a name="input_region_1_cidr"></a> [region\_1\_cidr](#input\_region\_1\_cidr) | VPC CIDR block to create for region 1 (only used when byo\_vpc = false) | `string` | `"10.202.0.0/16"` | no |
| <a name="input_region_1_private_route_table_ids"></a> [region\_1\_private\_route\_table\_ids](#input\_region\_1\_private\_route\_table\_ids) | Route table IDs associated with region 1 private subnets. Peering/TGW routes are added to these. Required when byo\_vpc = true. | `list(string)` | `[]` | no |
| <a name="input_region_1_private_subnet_ids"></a> [region\_1\_private\_subnet\_ids](#input\_region\_1\_private\_subnet\_ids) | Existing private subnet IDs in region 1 (≥3 across distinct AZs, required when byo\_vpc = true) | `list(string)` | `[]` | no |
| <a name="input_region_1_public_subnet_ids"></a> [region\_1\_public\_subnet\_ids](#input\_region\_1\_public\_subnet\_ids) | Existing public subnet IDs in region 1 (≥3 across distinct AZs, used for ALBs; required when byo\_vpc = true) | `list(string)` | `[]` | no |
| <a name="input_region_1_vpc_cidr"></a> [region\_1\_vpc\_cidr](#input\_region\_1\_vpc\_cidr) | CIDR block of the existing VPC in region 1 (required when byo\_vpc = true) | `string` | `""` | no |
| <a name="input_region_1_vpc_id"></a> [region\_1\_vpc\_id](#input\_region\_1\_vpc\_id) | Existing VPC ID in region 1 (required when byo\_vpc = true) | `string` | `""` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | If true, only one NAT gateway will be created per region to save on e.g. IPs, not good for HA. Only used when byo\_vpc = false. | `bool` | `false` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Cluster name prefix (passed through from var.cluster\_name) |
| <a name="output_networking_mode"></a> [networking\_mode](#output\_networking\_mode) | Cross-region networking mode: 'transit\_gateway' or 'vpc\_peering' |
| <a name="output_region_0"></a> [region\_0](#output\_region\_0) | AWS region for region 0 (owner) |
| <a name="output_region_0_internet_gateway_id"></a> [region\_0\_internet\_gateway\_id](#output\_region\_0\_internet\_gateway\_id) | Internet Gateway ID in region 0 (null in BYO mode — customer-managed) |
| <a name="output_region_0_private_route_table_ids"></a> [region\_0\_private\_route\_table\_ids](#output\_region\_0\_private\_route\_table\_ids) | Route table IDs associated with region 0 private subnets |
| <a name="output_region_0_private_subnet_ids"></a> [region\_0\_private\_subnet\_ids](#output\_region\_0\_private\_subnet\_ids) | Private subnet IDs in region 0 (used by ECS tasks and Aurora) |
| <a name="output_region_0_public_subnet_ids"></a> [region\_0\_public\_subnet\_ids](#output\_region\_0\_public\_subnet\_ids) | Public subnet IDs in region 0 (used for ALBs) |
| <a name="output_region_0_route53_resolver_endpoint_id"></a> [region\_0\_route53\_resolver\_endpoint\_id](#output\_region\_0\_route53\_resolver\_endpoint\_id) | Region 0 outbound resolver endpoint ID (null when enable\_cross\_region\_dns\_resolver = false) |
| <a name="output_region_0_transit_gateway_id"></a> [region\_0\_transit\_gateway\_id](#output\_region\_0\_transit\_gateway\_id) | TGW ID in region 0 (null when networking\_mode = vpc\_peering) |
| <a name="output_region_0_vpc_cidr"></a> [region\_0\_vpc\_cidr](#output\_region\_0\_vpc\_cidr) | VPC CIDR block in region 0 |
| <a name="output_region_0_vpc_id"></a> [region\_0\_vpc\_id](#output\_region\_0\_vpc\_id) | VPC ID in region 0 (created here or supplied via BYO) |
| <a name="output_region_1"></a> [region\_1](#output\_region\_1) | AWS region for region 1 (accepter) |
| <a name="output_region_1_internet_gateway_id"></a> [region\_1\_internet\_gateway\_id](#output\_region\_1\_internet\_gateway\_id) | Internet Gateway ID in region 1 (null in BYO mode — customer-managed) |
| <a name="output_region_1_private_route_table_ids"></a> [region\_1\_private\_route\_table\_ids](#output\_region\_1\_private\_route\_table\_ids) | Route table IDs associated with region 1 private subnets |
| <a name="output_region_1_private_subnet_ids"></a> [region\_1\_private\_subnet\_ids](#output\_region\_1\_private\_subnet\_ids) | Private subnet IDs in region 1 (used by ECS tasks and Aurora) |
| <a name="output_region_1_public_subnet_ids"></a> [region\_1\_public\_subnet\_ids](#output\_region\_1\_public\_subnet\_ids) | Public subnet IDs in region 1 (used for ALBs) |
| <a name="output_region_1_route53_resolver_endpoint_id"></a> [region\_1\_route53\_resolver\_endpoint\_id](#output\_region\_1\_route53\_resolver\_endpoint\_id) | Region 1 outbound resolver endpoint ID (null when enable\_cross\_region\_dns\_resolver = false) |
| <a name="output_region_1_transit_gateway_id"></a> [region\_1\_transit\_gateway\_id](#output\_region\_1\_transit\_gateway\_id) | TGW ID in region 1 (null when networking\_mode = vpc\_peering) |
| <a name="output_region_1_vpc_cidr"></a> [region\_1\_vpc\_cidr](#output\_region\_1\_vpc\_cidr) | VPC CIDR block in region 1 |
| <a name="output_region_1_vpc_id"></a> [region\_1\_vpc\_id](#output\_region\_1\_vpc\_id) | VPC ID in region 1 (created here or supplied via BYO) |
| <a name="output_vpc_peering_connection_id"></a> [vpc\_peering\_connection\_id](#output\_vpc\_peering\_connection\_id) | VPC Peering connection ID (null when networking\_mode = transit\_gateway) |
<!-- END_TF_DOCS -->
