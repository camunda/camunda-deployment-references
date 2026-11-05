# The management plane can share the VPC of an Orchestration Cluster or have its own. Use
# byo_vpc = true and your IDs to bring a VPC (see ../byo-vpc/network.tfvars).
prefix = "camunda-mgmt"
cidr   = "10.192.0.0/16"
