# Network Module

Creates the VPC for a Camunda deployment, or, with `byo_vpc = true`, creates nothing and re-exposes the VPC you already have. Either way the outputs are the same, so everything downstream (ECS, Aurora, load balancers, and also an EKS cluster) consumes one contract: `vpc_id`, `vpc_cidr`, `private_subnet_ids`, `public_subnet_ids`, `private_route_table_ids`.

## Bring your own VPC

```hcl
module "network" {
  source = "./aws/modules/network"

  byo_vpc                 = true
  vpc_id                  = "vpc-0123456789abcdef0"
  vpc_cidr                = "10.20.0.0/16"
  private_subnet_ids      = ["subnet-a", "subnet-b", "subnet-c"] # three distinct availability zones
  public_subnet_ids       = ["subnet-d", "subnet-e", "subnet-f"] # only for internet-facing load balancers
  private_route_table_ids = ["rtb-123"]                         # only for peering or transit gateway later
}
```

Requirements on your VPC: DNS support and DNS hostnames enabled, outbound access from the private subnets (NAT gateway or VPC endpoints), at least three private subnets in distinct availability zones.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | v6.7.3 |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_az_count"></a> [az\_count](#input\_az\_count) | Number of availability zones (and private/public subnet pairs) to create. Ignored in BYO mode. | `number` | `3` | no |
| <a name="input_byo_vpc"></a> [byo\_vpc](#input\_byo\_vpc) | When true, no VPC is created: the module validates and re-exposes the supplied vpc\_id and subnet IDs so that downstream stages consume one contract, whoever built the network. | `bool` | `false` | no |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | CIDR block of the VPC to create. Ignored in BYO mode. | `string` | `"10.200.0.0/16"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix of the VPC and its resources. Ignored in BYO mode. | `string` | `"camunda"` | no |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | BYO mode: private route table IDs. Only needed later, for peering or transit gateway routes. | `list(string)` | `[]` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | BYO mode: at least 3 private subnet IDs in distinct availability zones (ECS tasks, Aurora). | `list(string)` | `[]` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | BYO mode: at least 3 public subnet IDs in distinct availability zones with a route to an internet gateway (internet-facing load balancers). Can stay empty if nothing is exposed publicly. | `list(string)` | `[]` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Use one shared NAT gateway instead of one per availability zone. Cheaper, no zone redundancy for egress. Ignored in BYO mode. | `bool` | `false` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | BYO mode: CIDR block of the existing VPC (used for security group rules). | `string` | `""` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | BYO mode: ID of the existing VPC. | `string` | `""` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | Private route table IDs (needed for peering or transit gateway routes) |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs (ECS tasks, Aurora) |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs (internet-facing load balancers) |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | CIDR block of the VPC |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC |
<!-- END_TF_DOCS -->
