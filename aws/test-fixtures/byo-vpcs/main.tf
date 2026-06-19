# BYO-VPC test fixture.
#
# Creates two minimal VPCs (one per region) with the topology that the
# ecs-dual-region-fargate vpc/ state's byo_vpc = true mode expects:
#   - non-overlapping CIDRs
#   - >=3 private subnets across distinct AZs (used by ECS tasks and Aurora)
#   - >=3 public subnets across distinct AZs (used by NAT + ALB)
#   - private subnets have NAT egress; public subnets have IGW route
#
# Used by the BYO-VPC Terratest. Not a production reference — apply only
# to throwaway sandbox accounts.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_availability_zones" "region_0" {
  provider = aws.region_0
}

data "aws_availability_zones" "region_1" {
  provider = aws.region_1
}

module "vpc_region_0" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.1"

  providers = { aws = aws.region_0 }

  name = "${var.prefix}-byo-r0"
  cidr = var.region_0_cidr

  azs             = slice(data.aws_availability_zones.region_0.names, 0, 3)
  private_subnets = [for k, _ in slice(data.aws_availability_zones.region_0.names, 0, 3) : cidrsubnet(var.region_0_cidr, 3, k)]
  public_subnets  = [for k, _ in slice(data.aws_availability_zones.region_0.names, 0, 3) : cidrsubnet(var.region_0_cidr, 3, k + 3)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.tags
}

module "vpc_region_1" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.1"

  providers = { aws = aws.region_1 }

  name = "${var.prefix}-byo-r1"
  cidr = var.region_1_cidr

  azs             = slice(data.aws_availability_zones.region_1.names, 0, 3)
  private_subnets = [for k, _ in slice(data.aws_availability_zones.region_1.names, 0, 3) : cidrsubnet(var.region_1_cidr, 3, k)]
  public_subnets  = [for k, _ in slice(data.aws_availability_zones.region_1.names, 0, 3) : cidrsubnet(var.region_1_cidr, 3, k + 3)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.tags
}
