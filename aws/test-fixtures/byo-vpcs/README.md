# BYO-VPC test fixture

Throwaway Terraform config that creates two minimal VPCs (one per region) so the BYO-VPC end-to-end Terratest has something to plug into `byo_vpc = true` mode.

**Not a production reference.** Apply only against the sandbox AWS account.

## What it creates

| Per region | Resource |
|---|---|
| 1 | VPC with non-overlapping `/16` |
| 3 | Private subnets across 3 AZs (ECS tasks + Aurora) |
| 3 | Public subnets across 3 AZs (NAT + ALB) |
| 1 | NAT gateway (single, for cost) |
| 1 | Internet Gateway + route table associations |

Outputs match the field names the `ecs-dual-region-fargate` vpc/ state's BYO mode expects, so the Terratest can lift them directly into its tfvars.

## Used by

- `aws/containers/ecs-dual-region-fargate/test/src/helpers/byo_vpc_setup.go`
- `aws/containers/ecs-dual-region-fargate/test/src/byo_vpc_test.go`

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc_region_0"></a> [vpc\_region\_0](#module\_vpc\_region\_0) | terraform-aws-modules/vpc/aws | v6.6.1 |
| <a name="module_vpc_region_1"></a> [vpc\_region\_1](#module\_vpc\_region\_1) | terraform-aws-modules/vpc/aws | v6.6.1 |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_availability_zones.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS profile (null = default credential chain) | `string` | `null` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix for test resource names (typically the test's RunID) | `string` | n/a | yes |
| <a name="input_region_0"></a> [region\_0](#input\_region\_0) | Region 0 for the byo VPC fixture | `string` | `"eu-west-2"` | no |
| <a name="input_region_0_cidr"></a> [region\_0\_cidr](#input\_region\_0\_cidr) | n/a | `string` | `"10.150.0.0/16"` | no |
| <a name="input_region_1"></a> [region\_1](#input\_region\_1) | Region 1 for the byo VPC fixture | `string` | `"eu-west-3"` | no |
| <a name="input_region_1_cidr"></a> [region\_1\_cidr](#input\_region\_1\_cidr) | n/a | `string` | `"10.160.0.0/16"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | `{}` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_region_0_private_route_table_ids"></a> [region\_0\_private\_route\_table\_ids](#output\_region\_0\_private\_route\_table\_ids) | n/a |
| <a name="output_region_0_private_subnet_ids"></a> [region\_0\_private\_subnet\_ids](#output\_region\_0\_private\_subnet\_ids) | n/a |
| <a name="output_region_0_public_subnet_ids"></a> [region\_0\_public\_subnet\_ids](#output\_region\_0\_public\_subnet\_ids) | n/a |
| <a name="output_region_0_vpc_cidr"></a> [region\_0\_vpc\_cidr](#output\_region\_0\_vpc\_cidr) | n/a |
| <a name="output_region_0_vpc_id"></a> [region\_0\_vpc\_id](#output\_region\_0\_vpc\_id) | n/a |
| <a name="output_region_1_private_route_table_ids"></a> [region\_1\_private\_route\_table\_ids](#output\_region\_1\_private\_route\_table\_ids) | n/a |
| <a name="output_region_1_private_subnet_ids"></a> [region\_1\_private\_subnet\_ids](#output\_region\_1\_private\_subnet\_ids) | n/a |
| <a name="output_region_1_public_subnet_ids"></a> [region\_1\_public\_subnet\_ids](#output\_region\_1\_public\_subnet\_ids) | n/a |
| <a name="output_region_1_vpc_cidr"></a> [region\_1\_vpc\_cidr](#output\_region\_1\_vpc\_cidr) | n/a |
| <a name="output_region_1_vpc_id"></a> [region\_1\_vpc\_id](#output\_region\_1\_vpc\_id) | n/a |
<!-- END_TF_DOCS -->
