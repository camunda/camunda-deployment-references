################################
# VPC State Data Source       #
################################

data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = var.vpc_state_path
  }
}

# Convenience local — every downstream reference uses local.vpc.region_N_*
# rather than digging into data.terraform_remote_state.vpc.outputs each time.
locals {
  vpc = data.terraform_remote_state.vpc.outputs
}

# AZs derived from the (possibly customer-supplied) private subnets.
# Aurora needs them via primary_availability_zones; this works regardless
# of whether the VPC was created by us or supplied via BYO.

data "aws_subnet" "region_0_private" {
  count = length(local.vpc.region_0_private_subnet_ids)
  id    = local.vpc.region_0_private_subnet_ids[count.index]
}

data "aws_subnet" "region_1_private" {
  count    = length(local.vpc.region_1_private_subnet_ids)
  provider = aws.accepter
  id       = local.vpc.region_1_private_subnet_ids[count.index]
}
