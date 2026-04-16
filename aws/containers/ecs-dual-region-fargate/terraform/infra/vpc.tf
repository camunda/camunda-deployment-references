################################
# VPCs - One per Region       #
################################

# Region 0 (owner)
data "aws_availability_zones" "region_0" {}

module "vpc_region_0" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.1"

  name = "${local.prefix_region_0}-vpc"
  cidr = local.owner.vpc_cidr_block

  azs             = slice(data.aws_availability_zones.region_0.names, 0, 3)
  private_subnets = [for k, v in slice(data.aws_availability_zones.region_0.names, 0, 3) : cidrsubnet(local.owner.vpc_cidr_block, 3, k)]
  public_subnets  = [for k, v in slice(data.aws_availability_zones.region_0.names, 0, 3) : cidrsubnet(local.owner.vpc_cidr_block, 3, k + 3)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Region 1 (accepter)
data "aws_availability_zones" "region_1" {
  provider = aws.accepter
}

module "vpc_region_1" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.1"

  providers = {
    aws = aws.accepter
  }

  name = "${local.prefix_region_1}-vpc"
  cidr = local.accepter.vpc_cidr_block

  azs             = slice(data.aws_availability_zones.region_1.names, 0, 3)
  private_subnets = [for k, v in slice(data.aws_availability_zones.region_1.names, 0, 3) : cidrsubnet(local.accepter.vpc_cidr_block, 3, k)]
  public_subnets  = [for k, v in slice(data.aws_availability_zones.region_1.names, 0, 3) : cidrsubnet(local.accepter.vpc_cidr_block, 3, k + 3)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true
}
