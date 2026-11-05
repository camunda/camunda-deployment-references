# A VPC for region B. The CIDR must not overlap region A's. Use byo_vpc = true and the IDs
# of an existing VPC instead if you have one (see ../../byo-vpc/network.tfvars).
prefix = "camunda-demo-b"
cidr   = "10.191.0.0/16"
