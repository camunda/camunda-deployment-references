data "aws_availability_zones" "available" {}

locals {
  name = "${var.prefix}-vpc"

  vpc_cidr = var.cidr_blocks
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_servicequotas_service_quota" "elastic_ip_quota" {
  service_code = "ec2"
  quota_code   = "L-0263D0A3" # Quota code for Elastic IP addresses per region
}

data "aws_eips" "current_usage" {}

# Data source to check if the VPC exists
data "aws_vpcs" "current_vpcs" {
  tags = {
    Name = local.name
  }
}

check "elastic_ip_quota_check" {
  # Only check the condition when no existing vpc is there
  assert {
    condition = length(data.aws_vpcs.current_vpcs.ids) > 0 || (
      (data.aws_servicequotas_service_quota.elastic_ip_quota.value - length(data.aws_eips.current_usage.public_ips)) >= length(local.azs)
    )
    error_message = "Not enough available Elastic IPs to cover required NAT gateways (need: ${length(local.azs)}, have: ${(data.aws_servicequotas_service_quota.elastic_ip_quota.value - length(data.aws_eips.current_usage.public_ips))})."
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, length(local.azs), k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, length(local.azs), k + length(local.azs))]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # Enable DNS support for EFS
  enable_dns_hostnames = true
  enable_dns_support   = true
}
