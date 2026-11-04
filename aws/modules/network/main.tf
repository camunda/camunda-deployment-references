data "aws_availability_zones" "available" {
  count = var.byo_vpc ? 0 : 1
  state = "available"
}

locals {
  azs = var.byo_vpc ? [] : slice(data.aws_availability_zones.available[0].names, 0, var.az_count)
}

module "vpc" {
  count = var.byo_vpc ? 0 : 1

  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.7.3"

  name = "${var.name}-vpc"
  cidr = var.cidr

  azs             = local.azs
  private_subnets = [for k, _ in local.azs : cidrsubnet(var.cidr, 3, k)]
  public_subnets  = [for k, _ in local.azs : cidrsubnet(var.cidr, 3, k + var.az_count)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # DNS support is required for EFS and Cloud Map
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Fail early when the BYO inputs are incomplete, or when they would be silently ignored.
check "byo_vpc_required_inputs" {
  assert {
    condition = !var.byo_vpc || (
      var.vpc_id != "" &&
      var.vpc_cidr != "" &&
      length(var.private_subnet_ids) >= 3
    )
    error_message = "byo_vpc = true requires vpc_id, vpc_cidr and at least 3 private_subnet_ids (distinct availability zones)."
  }
}

check "create_vpc_inputs_clean" {
  assert {
    condition = var.byo_vpc || (
      var.vpc_id == "" &&
      var.vpc_cidr == "" &&
      length(var.private_subnet_ids) == 0 &&
      length(var.public_subnet_ids) == 0 &&
      length(var.private_route_table_ids) == 0
    )
    error_message = "byo_vpc = false but BYO inputs (vpc_id, vpc_cidr, subnet or route table IDs) are set. They would be ignored: clear them or set byo_vpc = true."
  }
}
