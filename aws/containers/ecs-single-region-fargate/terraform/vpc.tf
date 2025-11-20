data "aws_availability_zones" "available" {}

locals {
  name = "${var.prefix}-vpc"

  vpc_cidr = var.cidr_blocks
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.5.1"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k + 4)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # Enable DNS support for EFS
  enable_dns_hostnames = true
  enable_dns_support   = true
}
