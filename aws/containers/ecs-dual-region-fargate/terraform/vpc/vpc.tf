################################################################
# VPCs - one per region                                         #
#                                                                #
# Created only when byo_vpc = false. In BYO mode, the locals    #
# resolve to var.region_N_vpc_id etc. and no AWS VPC resources  #
# are created here. The rest of this state (peering, TGW,       #
# Route 53 Resolver) still runs against the supplied VPC IDs.   #
################################################################

# Region 0 (owner)
data "aws_availability_zones" "region_0" {
  count = var.byo_vpc ? 0 : 1
}

module "vpc_region_0" {
  count = var.byo_vpc ? 0 : 1

  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.1"

  name = "${local.prefix_region_0}-vpc"
  cidr = var.region_0_cidr

  azs             = slice(data.aws_availability_zones.region_0[0].names, 0, 3)
  private_subnets = [for k, v in slice(data.aws_availability_zones.region_0[0].names, 0, 3) : cidrsubnet(var.region_0_cidr, 3, k)]
  public_subnets  = [for k, v in slice(data.aws_availability_zones.region_0[0].names, 0, 3) : cidrsubnet(var.region_0_cidr, 3, k + 3)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Region 1 (accepter)
data "aws_availability_zones" "region_1" {
  count    = var.byo_vpc ? 0 : 1
  provider = aws.accepter
}

module "vpc_region_1" {
  count = var.byo_vpc ? 0 : 1

  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.1"

  providers = {
    aws = aws.accepter
  }

  name = "${local.prefix_region_1}-vpc"
  cidr = var.region_1_cidr

  azs             = slice(data.aws_availability_zones.region_1[0].names, 0, 3)
  private_subnets = [for k, v in slice(data.aws_availability_zones.region_1[0].names, 0, 3) : cidrsubnet(var.region_1_cidr, 3, k)]
  public_subnets  = [for k, v in slice(data.aws_availability_zones.region_1[0].names, 0, 3) : cidrsubnet(var.region_1_cidr, 3, k + 3)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true
}
