# clusters

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_database_region_0"></a> [database\_region\_0](#module\_database\_region\_0) | ../../../../modules/aurora-global-member | n/a |
| <a name="module_database_region_1"></a> [database\_region\_1](#module\_database\_region\_1) | ../../../../modules/aurora-global-member | n/a |
| <a name="module_database_region_2"></a> [database\_region\_2](#module\_database\_region\_2) | ../../../../modules/aurora-global-member | n/a |
| <a name="module_database_region_3"></a> [database\_region\_3](#module\_database\_region\_3) | ../../../../modules/aurora-global-member | n/a |
| <a name="module_eks_cluster_region_0"></a> [eks\_cluster\_region\_0](#module\_eks\_cluster\_region\_0) | ../../../../modules/eks-cluster | n/a |
| <a name="module_eks_cluster_region_1"></a> [eks\_cluster\_region\_1](#module\_eks\_cluster\_region\_1) | ../../../../modules/eks-cluster | n/a |
| <a name="module_eks_cluster_region_2"></a> [eks\_cluster\_region\_2](#module\_eks\_cluster\_region\_2) | ../../../../modules/eks-cluster | n/a |
| <a name="module_eks_cluster_region_3"></a> [eks\_cluster\_region\_3](#module\_eks\_cluster\_region\_3) | ../../../../modules/eks-cluster | n/a |
| <a name="module_tgw_hub_region_0"></a> [tgw\_hub\_region\_0](#module\_tgw\_hub\_region\_0) | ../../../../modules/transit-gateway-hub | n/a |
| <a name="module_tgw_hub_region_1"></a> [tgw\_hub\_region\_1](#module\_tgw\_hub\_region\_1) | ../../../../modules/transit-gateway-hub | n/a |
| <a name="module_tgw_hub_region_2"></a> [tgw\_hub\_region\_2](#module\_tgw\_hub\_region\_2) | ../../../../modules/transit-gateway-hub | n/a |
| <a name="module_tgw_hub_region_3"></a> [tgw\_hub\_region\_3](#module\_tgw\_hub\_region\_3) | ../../../../modules/transit-gateway-hub | n/a |
| <a name="module_tgw_peering_0_1"></a> [tgw\_peering\_0\_1](#module\_tgw\_peering\_0\_1) | ../../../../modules/transit-gateway-peering | n/a |
| <a name="module_tgw_peering_0_2"></a> [tgw\_peering\_0\_2](#module\_tgw\_peering\_0\_2) | ../../../../modules/transit-gateway-peering | n/a |
| <a name="module_tgw_peering_0_3"></a> [tgw\_peering\_0\_3](#module\_tgw\_peering\_0\_3) | ../../../../modules/transit-gateway-peering | n/a |
| <a name="module_tgw_peering_1_2"></a> [tgw\_peering\_1\_2](#module\_tgw\_peering\_1\_2) | ../../../../modules/transit-gateway-peering | n/a |
| <a name="module_tgw_peering_1_3"></a> [tgw\_peering\_1\_3](#module\_tgw\_peering\_1\_3) | ../../../../modules/transit-gateway-peering | n/a |
| <a name="module_tgw_peering_2_3"></a> [tgw\_peering\_2\_3](#module\_tgw\_peering\_2\_3) | ../../../../modules/transit-gateway-peering | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_rds_global_cluster.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_global_cluster) | resource |
| [aws_vpc_security_group_ingress_rule.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.region_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.region_3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_password.database](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [time_sleep.wait_for_database_writer](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_active_region_count"></a> [active\_region\_count](#input\_active\_region\_count) | Number of region slots actually deployed. Must be at least<br/>`length(var.regions) - 1` so that every Zeebe partition keeps a majority of<br/>its replicas, and at most `length(var.regions)`.<br/><br/>Deploying fewer regions than slots is the "growth" mode: the cluster runs<br/>with one replica missing per partition and tolerates no further region<br/>loss until the remaining regions are activated. | `number` | `3` | no |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS Profile to use (null = use default credential chain) | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster to prefix resources. Each region appends its short\_name. | `string` | n/a | yes |
| <a name="input_database_engine_version"></a> [database\_engine\_version](#input\_database\_engine\_version) | Aurora PostgreSQL engine version. Camunda 8.10 supports PostgreSQL 15 to 18. | `string` | `"17.9"` | no |
| <a name="input_database_iam_auth_enabled"></a> [database\_iam\_auth\_enabled](#input\_database\_iam\_auth\_enabled) | Whether IAM database authentication is enabled on the Aurora clusters.<br/><br/>Kept off by default: the reference deployment authenticates with a password<br/>stored in a Kubernetes secret, which is the portable path that works with<br/>any RDBMS. Turning it on additionally requires IRSA roles carrying<br/>rds-db:connect for every regional cluster; see<br/>aws/kubernetes/eks-single-region-irsa for the IRSA pattern. | `bool` | `false` | no |
| <a name="input_database_instance_class"></a> [database\_instance\_class](#input\_database\_instance\_class) | Instance class of the Aurora cluster instances | `string` | `"db.r6g.large"` | no |
| <a name="input_database_instances_per_region"></a> [database\_instances\_per\_region](#input\_database\_instances\_per\_region) | Number of Aurora instances per region. Use at least 2 in production for intra-region failover. | `number` | `1` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | Name of the database backing the Camunda secondary storage | `string` | `"camunda"` | no |
| <a name="input_database_region_slots"></a> [database\_region\_slots](#input\_database\_region\_slots) | Region slots that host an Aurora Global Database member. Must be a subset of<br/>the active region slots and must contain slot 0.<br/><br/>Slot 0 is always the writer. That is not a limitation of Aurora, which can<br/>promote any member, but of Terraform: the secondary members have to wait for<br/>the writer to exist before they can attach to the global cluster, and that<br/>ordering has to reference a statically known module. Pinning the writer to<br/>slot 0 keeps the dependency correct by construction. A failover still moves<br/>the writer wherever you want at runtime; see procedure/failover.sh.<br/><br/>Defaults to two regions: Aurora Global Database is not available in every<br/>AWS region, and the Zeebe topology does not require a database member in<br/>each region. Brokers in regions without a member reach the writer over the<br/>Transit Gateway mesh. | `list(number)` | <pre>[<br/>  0,<br/>  1<br/>]</pre> | no |
| <a name="input_database_username"></a> [database\_username](#input\_database\_username) | Master username of the Aurora Global Database | `string` | `"camunda"` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_deploy_database"></a> [deploy\_database](#input\_deploy\_database) | Whether to create the Aurora Global Database. Set to false to bring your own RDBMS. | `bool` | `true` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version to use | `string` | `"1.36"` | no |
| <a name="input_np_capacity_type"></a> [np\_capacity\_type](#input\_np\_capacity\_type) | Allows setting the capacity type to ON\_DEMAND or SPOT to determine stable nodes | `string` | `"ON_DEMAND"` | no |
| <a name="input_np_desired_node_count"></a> [np\_desired\_node\_count](#input\_np\_desired\_node\_count) | Desired number of nodes in the node pool | `number` | `4` | no |
| <a name="input_np_instance_types"></a> [np\_instance\_types](#input\_np\_instance\_types) | Instance types for the node pool | `list(string)` | <pre>[<br/>  "m6i.xlarge"<br/>]</pre> | no |
| <a name="input_np_max_node_count"></a> [np\_max\_node\_count](#input\_np\_max\_node\_count) | Maximum number of nodes in the node pool | `number` | `10` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Ordered list of region slots. Index 0 is region slot 0, index 1 is region<br/>slot 1, and so on. The list defines the named zones of the Camunda cluster<br/>and is immutable for its lifetime; growth activates a zone declared here<br/>rather than adding a new one later.<br/><br/>`vpc_cidr_block` and `service_cidr_block` must not overlap across regions:<br/>Transit Gateway cannot route duplicate prefixes, and Submariner runs<br/>without Globalnet so every CIDR it learns has to identify exactly one<br/>cluster.<br/><br/>There is no separate pod range. With the AWS VPC CNI a pod address IS a VPC<br/>address, so pods are reachable across regions over the Transit Gateway with<br/>no overlay; see ../../README.md, section "Cross-region networking".<br/><br/>`short_name` is used to suffix cluster and resource names and must be a<br/>valid DNS label. | <pre>list(object({<br/>    region             = string<br/>    short_name         = string<br/>    vpc_cidr_block     = string<br/>    service_cidr_block = string<br/>  }))</pre> | <pre>[<br/>  {<br/>    "region": "eu-west-2",<br/>    "service_cidr_block": "10.190.0.0/16",<br/>    "short_name": "london",<br/>    "vpc_cidr_block": "10.192.0.0/16"<br/>  },<br/>  {<br/>    "region": "eu-west-3",<br/>    "service_cidr_block": "10.200.0.0/16",<br/>    "short_name": "paris",<br/>    "vpc_cidr_block": "10.202.0.0/16"<br/>  },<br/>  {<br/>    "region": "eu-central-2",<br/>    "service_cidr_block": "10.210.0.0/16",<br/>    "short_name": "zurich",<br/>    "vpc_cidr_block": "10.212.0.0/16"<br/>  }<br/>]</pre> | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | If true, only one NAT gateway will be created to save on e.g. IPs, not good for HA | `bool` | `false` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_active_region_count"></a> [active\_region\_count](#output\_active\_region\_count) | Number of region slots currently deployed |
| <a name="output_all_cidr_blocks"></a> [all\_cidr\_blocks](#output\_all\_cidr\_blocks) | Every VPC and Kubernetes service CIDR of the active regions, used to build database firewall rules |
| <a name="output_camunda_rdbms_url"></a> [camunda\_rdbms\_url](#output\_camunda\_rdbms\_url) | JDBC URL for `orchestration.data.secondaryStorage.rdbms.url`.<br/><br/>It uses the AWS Advanced JDBC Wrapper with the `failover` plugin and the<br/>instance host patterns of every Aurora Global member, so that a global<br/>failover is followed transparently and Camunda never has to be<br/>reconfigured. Replace this URL with any single-writer endpoint to run the<br/>same architecture on a different database. |
| <a name="output_cluster_names"></a> [cluster\_names](#output\_cluster\_names) | EKS cluster name per active region slot; a slot that is not deployed yet has no key here |
| <a name="output_database_cluster_identifiers"></a> [database\_cluster\_identifiers](#output\_database\_cluster\_identifiers) | Aurora cluster identifier per region slot hosting a database member |
| <a name="output_database_global_cluster_id"></a> [database\_global\_cluster\_id](#output\_database\_global\_cluster\_id) | Identifier of the Aurora Global Database, consumed by the failover and failback procedures |
| <a name="output_database_name"></a> [database\_name](#output\_database\_name) | Name of the database backing the Camunda secondary storage |
| <a name="output_database_password"></a> [database\_password](#output\_database\_password) | Master password of the Aurora Global Database |
| <a name="output_database_username"></a> [database\_username](#output\_database\_username) | Master username of the Aurora Global Database |
| <a name="output_database_writer_endpoint"></a> [database\_writer\_endpoint](#output\_database\_writer\_endpoint) | Writer endpoint of the current Aurora Global Database primary |
| <a name="output_oidc_provider_arns"></a> [oidc\_provider\_arns](#output\_oidc\_provider\_arns) | OIDC provider ARN per active region slot, used to bind IRSA roles |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs per active region slot, used by the database root module |
| <a name="output_region_slot_count"></a> [region\_slot\_count](#output\_region\_slot\_count) | Number of region slots in the fixed zone topology. The deployment can<br/>activate a zone declared up front, but does not add zones later. |
| <a name="output_regions"></a> [regions](#output\_regions) | Region slot definitions of the ACTIVE regions, indexed by slot number |
| <a name="output_service_cidr_blocks"></a> [service\_cidr\_blocks](#output\_service\_cidr\_blocks) | Kubernetes service CIDR block per active region slot |
| <a name="output_transit_gateway_ids"></a> [transit\_gateway\_ids](#output\_transit\_gateway\_ids) | Transit Gateway ID per active region slot |
| <a name="output_vpc_cidr_blocks"></a> [vpc\_cidr\_blocks](#output\_vpc\_cidr\_blocks) | VPC CIDR block per active region slot |
| <a name="output_vpc_ids"></a> [vpc\_ids](#output\_vpc\_ids) | VPC ID per active region slot; a slot that is not deployed yet has no key here |
| <a name="output_zone_names"></a> [zone\_names](#output\_zone\_names) | Zone name per slot, in slot order, for EVERY slot including ones not<br/>deployed yet.<br/><br/>Deliberately not the same set as the active regions. The Camunda zone list<br/>describes the whole topology so that the replicas of an undeployed zone are<br/>reserved rather than redistributed; feeding it only the active regions<br/>would silently build a smaller cluster and lose the growth property. |
<!-- END_TF_DOCS -->
