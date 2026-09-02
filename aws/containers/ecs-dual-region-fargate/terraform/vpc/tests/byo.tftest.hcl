# BYO-VPC mode tests.
#
# When byo_vpc = true, the terraform-aws-modules/vpc/aws module instantiations
# are skipped (count = 0). The locals resolve to the supplied variables and the
# outputs pass them through verbatim. This file asserts:
#   1. Outputs match the supplied inputs (the contract).
#   2. No VPC module resources are planned (locals point at vars, not module outputs).
#   3. Peering / TGW is still planned between the supplied VPC IDs.
#
# These tests are deterministic — they never touch the vpc/aws module's internals.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

# Canonical BYO fixture reused across runs.
variables {
  cluster_name = "test-byo"
  byo_vpc      = true

  region_0_vpc_id                  = "vpc-aaaaaaaa"
  region_0_vpc_cidr                = "10.50.0.0/16"
  region_0_private_subnet_ids      = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  region_0_public_subnet_ids       = ["subnet-aaa4aaaa", "subnet-aaa5aaaa", "subnet-aaa6aaaa"]
  region_0_private_route_table_ids = ["rtb-aaa1aaaa", "rtb-aaa2aaaa", "rtb-aaa3aaaa"]

  region_1_vpc_id                  = "vpc-bbbbbbbb"
  region_1_vpc_cidr                = "10.60.0.0/16"
  region_1_private_subnet_ids      = ["subnet-bbb1bbbb", "subnet-bbb2bbbb", "subnet-bbb3bbbb"]
  region_1_public_subnet_ids       = ["subnet-bbb4bbbb", "subnet-bbb5bbbb", "subnet-bbb6bbbb"]
  region_1_private_route_table_ids = ["rtb-bbb1bbbb", "rtb-bbb2bbbb", "rtb-bbb3bbbb"]
}

run "byo_passthrough_outputs_match_inputs" {
  command = plan

  assert {
    condition     = output.region_0_vpc_id == var.region_0_vpc_id
    error_message = "region_0_vpc_id output should equal supplied var.region_0_vpc_id when byo_vpc = true"
  }

  assert {
    condition     = output.region_0_vpc_cidr == var.region_0_vpc_cidr
    error_message = "region_0_vpc_cidr output should equal supplied var.region_0_vpc_cidr"
  }

  assert {
    condition     = output.region_0_private_subnet_ids == var.region_0_private_subnet_ids
    error_message = "region_0_private_subnet_ids passthrough broken"
  }

  assert {
    condition     = output.region_0_public_subnet_ids == var.region_0_public_subnet_ids
    error_message = "region_0_public_subnet_ids passthrough broken"
  }

  assert {
    condition     = output.region_0_private_route_table_ids == var.region_0_private_route_table_ids
    error_message = "region_0_private_route_table_ids passthrough broken"
  }

  assert {
    condition     = output.region_1_vpc_id == var.region_1_vpc_id
    error_message = "region_1_vpc_id passthrough broken"
  }

  assert {
    condition     = output.region_1_vpc_cidr == var.region_1_vpc_cidr
    error_message = "region_1_vpc_cidr passthrough broken"
  }
}

run "byo_internet_gateway_outputs_null" {
  command = plan

  assert {
    condition     = output.region_0_internet_gateway_id == null
    error_message = "region_0_internet_gateway_id should be null in BYO mode (customer-managed)"
  }

  assert {
    condition     = output.region_1_internet_gateway_id == null
    error_message = "region_1_internet_gateway_id should be null in BYO mode (customer-managed)"
  }
}

run "byo_skips_vpc_module_region_0" {
  command = plan

  assert {
    condition     = length(module.vpc_region_0) == 0
    error_message = "module.vpc_region_0 should have count = 0 when byo_vpc = true"
  }
}

run "byo_skips_vpc_module_region_1" {
  command = plan

  assert {
    condition     = length(module.vpc_region_1) == 0
    error_message = "module.vpc_region_1 should have count = 0 when byo_vpc = true"
  }
}

run "byo_with_vpc_peering_creates_peering_between_supplied_ids" {
  command = plan

  variables {
    networking_mode = "vpc_peering"
  }

  assert {
    condition     = aws_vpc_peering_connection.cross_region[0].vpc_id == var.region_0_vpc_id
    error_message = "Peering connection requester VPC should be the supplied region_0_vpc_id"
  }

  assert {
    condition     = aws_vpc_peering_connection.cross_region[0].peer_vpc_id == var.region_1_vpc_id
    error_message = "Peering connection peer VPC should be the supplied region_1_vpc_id"
  }

  assert {
    condition     = length(module.transit_gateway) == 0
    error_message = "TGW module should be empty when networking_mode = vpc_peering"
  }
}

run "byo_with_transit_gateway_creates_attachments_targeting_supplied_subnets" {
  command = plan

  variables {
    networking_mode = "transit_gateway"
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.region_0[0].vpc_id == var.region_0_vpc_id
    error_message = "TGW attachment in region 0 should target the supplied region_0_vpc_id"
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.region_0[0].subnet_ids == toset(var.region_0_private_subnet_ids)
    error_message = "TGW attachment in region 0 should use the supplied private subnets"
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.region_1[0].vpc_id == var.region_1_vpc_id
    error_message = "TGW attachment in region 1 should target the supplied region_1_vpc_id"
  }

  assert {
    condition     = length(aws_vpc_peering_connection.cross_region) == 0
    error_message = "VPC peering connection should be empty when networking_mode = transit_gateway"
  }
}
