# peering

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_route.cluster_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.cluster_1_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.cluster_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.cluster_2_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_vpc_peering_connection.cluster_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [aws_vpc_peering_connection_accepter.cluster_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_accepter) | resource |
| [aws_vpc_peering_connection_options.cluster_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_options) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_1_primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_2_primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_route_tables.cluster_1_private_route_tables](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route_tables) | data source |
| [aws_route_tables.cluster_1_public_route_tables](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route_tables) | data source |
| [aws_route_tables.cluster_2_private_route_tables](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route_tables) | data source |
| [aws_route_tables.cluster_2_public_route_tables](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route_tables) | data source |
| [aws_security_groups.cluster_1_worker_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/security_groups) | data source |
| [aws_security_groups.cluster_2_worker_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/security_groups) | data source |
| [aws_vpc.cluster_1_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |
| [aws_vpc.cluster_2_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_1_region"></a> [cluster\_1\_region](#input\_cluster\_1\_region) | Region of the cluster 1 | `string` | `"us-east-1"` | no |
| <a name="input_cluster_1_vpc_id"></a> [cluster\_1\_vpc\_id](#input\_cluster\_1\_vpc\_id) | VPC ID of the cluster 1 | `string` | n/a | yes |
| <a name="input_cluster_2_region"></a> [cluster\_2\_region](#input\_cluster\_2\_region) | Region of the cluster 2 | `string` | `"us-east-2"` | no |
| <a name="input_cluster_2_vpc_id"></a> [cluster\_2\_vpc\_id](#input\_cluster\_2\_vpc\_id) | VPC ID of the cluster 2 | `string` | n/a | yes |
## Outputs

No outputs.
<!-- END_TF_DOCS -->
