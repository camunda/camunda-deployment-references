# peering

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_route.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.accepter_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.owner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.owner_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_vpc_peering_connection.owner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [aws_vpc_peering_connection_accepter.accepter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection_accepter) | resource |
| [aws_vpc_security_group_ingress_rule.accepter_eks_primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.owner_eks_primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_accepter"></a> [accepter](#input\_accepter) | Information for the accepter VPC | <pre>object({<br/>    region                  = string<br/>    vpc_cidr_block          = string<br/>    vpc_id                  = string<br/>    security_group_id       = string<br/>    public_route_table_id   = string<br/>    private_route_table_ids = set(string)<br/>  })</pre> | n/a | yes |
| <a name="input_cluster_set_name"></a> [cluster\_set\_name](#input\_cluster\_set\_name) | Name of the cluster set | `string` | `"cl-oc"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Information for the owner VPC | <pre>object({<br/>    region                  = string<br/>    vpc_cidr_block          = string<br/>    vpc_id                  = string<br/>    security_group_id       = string<br/>    public_route_table_id   = string<br/>    private_route_table_ids = set(string)<br/>  })</pre> | n/a | yes |
## Outputs

No outputs.
<!-- END_TF_DOCS -->
