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
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_sg_submariner_rules"></a> [sg\_submariner\_rules](#input\_sg\_submariner\_rules) | n/a | <pre>list(object({<br/>    from_port   = number<br/>    to_port     = number<br/>    protocol    = string<br/>    description = string<br/>  }))</pre> | <pre>[<br/>  {<br/>    "description": "Submariner Pod traffic encapsulation",<br/>    "from_port": 4800,<br/>    "protocol": "udp",<br/>    "to_port": 4800<br/>  },<br/>  {<br/>    "description": "Submariner NAT Traversal encapsulation",<br/>    "from_port": 4500,<br/>    "protocol": "udp",<br/>    "to_port": 4500<br/>  },<br/>  {<br/>    "description": "Submariner NAT Traversal discovery",<br/>    "from_port": 4490,<br/>    "protocol": "udp",<br/>    "to_port": 4490<br/>  },<br/>  {<br/>    "description": "IPSec IKE traffic for secure tunnels",<br/>    "from_port": 500,<br/>    "protocol": "udp",<br/>    "to_port": 500<br/>  },<br/>  {<br/>    "description": "Ingress communication to Gateway nodes",<br/>    "from_port": 8080,<br/>    "protocol": "tcp",<br/>    "to_port": 8080<br/>  },<br/>  {<br/>    "description": "ESP protocol for secure communication between gateways",<br/>    "from_port": -1,<br/>    "protocol": "50",<br/>    "to_port": -1<br/>  },<br/>  {<br/>    "description": "OpenShift API access",<br/>    "from_port": 443,<br/>    "protocol": "tcp",<br/>    "to_port": 443<br/>  },<br/>  {<br/>    "description": "Allow ICMP ping",<br/>    "from_port": -1,<br/>    "protocol": "icmp",<br/>    "to_port": -1<br/>  }<br/>]</pre> | no |
## Outputs

No outputs.
<!-- END_TF_DOCS -->
