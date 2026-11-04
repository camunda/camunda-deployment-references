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
<!-- END_TF_DOCS -->
