prefix   = "camunda-demo"
region_a = "eu-west-1"
region_b = "eu-north-1"

# Outputs of the network layers of both regions.
vpc_id_a                  = "vpc-0aaa"
vpc_cidr_a                = "10.190.0.0/16"
private_subnet_ids_a      = ["subnet-a1", "subnet-a2", "subnet-a3"]
private_route_table_ids_a = ["rtb-a1", "rtb-a2", "rtb-a3"]
vpc_id_b                  = "vpc-0bbb"
vpc_cidr_b                = "10.191.0.0/16"
private_subnet_ids_b      = ["subnet-b1", "subnet-b2", "subnet-b3"]
private_route_table_ids_b = ["rtb-b1", "rtb-b2", "rtb-b3"]

# <prefix of each camunda layer>-oc.service.local
service_discovery_domain_a = "camunda-demo-oc.service.local"
service_discovery_domain_b = "camunda-demo-b-oc.service.local"
