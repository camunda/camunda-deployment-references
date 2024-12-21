data "aws_availability_zones" "available" {}

locals {
  name = "${var.prefix}-vpc"

  vpc_cidr = var.cidr_blocks
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Example = local.name
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v5.17.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k + 4)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  create_flow_log_cloudwatch_iam_role  = var.enable_vpc_logging
  create_flow_log_cloudwatch_log_group = var.enable_vpc_logging

  flow_log_cloudwatch_log_group_kms_key_id        = var.enable_vpc_logging ? aws_kms_key.main.id : null
  flow_log_cloudwatch_log_group_name_prefix       = var.enable_vpc_logging ? var.prefix : null
  flow_log_cloudwatch_log_group_retention_in_days = var.enable_vpc_logging ? 30 : null

  tags = local.tags
}
