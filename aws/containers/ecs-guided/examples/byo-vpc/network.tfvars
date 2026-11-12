# I already have a VPC: the network stage creates nothing, it validates these values and
# exposes them. Everything after it works unchanged.
prefix  = "camunda-demo"
byo_vpc = true

vpc_id   = "vpc-0123456789abcdef0"
vpc_cidr = "10.20.0.0/16"

# Three distinct availability zones.
private_subnet_ids = ["subnet-0aaa", "subnet-0bbb", "subnet-0ccc"]

# Only for the internet-facing load balancers: subnets with a route to an internet gateway.
public_subnet_ids = ["subnet-0ddd", "subnet-0eee", "subnet-0fff"]

# Only needed later, for peering or a transit gateway.
private_route_table_ids = ["rtb-0123"]
