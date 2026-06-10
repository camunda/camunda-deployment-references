# Greenfield mode tests.
#
# When byo_vpc = false (default), the terraform-aws-modules/vpc/aws modules
# are instantiated. These tests rely on locals branching behavior, output
# wiring, and the conditional creation of TGW vs. peering. They do not assert
# on the internal resources of the vpc/aws community module — that module
# already has its own test suite upstream.
#
# Data sources (data.aws_availability_zones) are overridden so AZ-derived
# subnet counts are deterministic.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

override_data {
  target = data.aws_availability_zones.region_0[0]
  values = {
    names = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }
}

override_data {
  target = data.aws_availability_zones.region_1[0]
  values = {
    names = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }
}

variables {
  cluster_name = "test-greenfield"
}

run "default_plan_succeeds" {
  command = plan

  assert {
    condition     = output.networking_mode == "transit_gateway"
    error_message = "Default networking_mode should be transit_gateway"
  }
}

run "vpc_peering_mode_no_tgw" {
  command = plan

  variables {
    networking_mode = "vpc_peering"
  }

  assert {
    condition     = length(module.transit_gateway) == 0
    error_message = "TGW module should be empty when networking_mode = vpc_peering"
  }

  assert {
    condition     = length(aws_vpc_peering_connection.cross_region) == 1
    error_message = "Peering connection should be planned when networking_mode = vpc_peering"
  }

  # Cannot assert on output.vpc_peering_connection_id here — its value is unknown
  # at plan time (computed by the AWS API on apply). The resource-count check above
  # is the plan-time equivalent.
}

run "transit_gateway_mode_no_peering" {
  command = plan

  variables {
    networking_mode = "transit_gateway"
  }

  assert {
    condition     = length(module.transit_gateway) == 1
    error_message = "TGW module should be instantiated when networking_mode = transit_gateway"
  }

  assert {
    condition     = length(aws_vpc_peering_connection.cross_region) == 0
    error_message = "VPC peering connection should be empty when networking_mode = transit_gateway"
  }
}

run "cross_region_dns_off_skips_resolver_sgs" {
  command = plan

  # default: enable_cross_region_dns_resolver = false

  assert {
    condition     = length(aws_security_group.dns_resolver_region_0) == 0
    error_message = "DNS resolver SG region 0 should be empty when enable_cross_region_dns_resolver = false"
  }

  assert {
    condition     = length(aws_security_group.dns_resolver_region_1) == 0
    error_message = "DNS resolver SG region 1 should be empty when enable_cross_region_dns_resolver = false"
  }

  assert {
    condition     = length(aws_route53_resolver_endpoint.outbound_region_0) == 0
    error_message = "Outbound resolver endpoint region 0 should be empty when resolver disabled"
  }
}

run "cross_region_dns_on_creates_resolver_sgs" {
  command = plan

  variables {
    enable_cross_region_dns_resolver = true
  }

  assert {
    condition     = length(aws_security_group.dns_resolver_region_0) == 1
    error_message = "DNS resolver SG region 0 should be planned when enable_cross_region_dns_resolver = true"
  }

  assert {
    condition     = length(aws_security_group.dns_resolver_region_1) == 1
    error_message = "DNS resolver SG region 1 should be planned when enable_cross_region_dns_resolver = true"
  }

  assert {
    condition     = length(aws_route53_resolver_endpoint.outbound_region_0) == 1
    error_message = "Outbound resolver endpoint region 0 should be planned"
  }

  assert {
    condition     = length(aws_route53_resolver_endpoint.outbound_region_1) == 1
    error_message = "Outbound resolver endpoint region 1 should be planned"
  }
}

run "vpc_modules_instantiated_in_greenfield" {
  command = plan

  assert {
    condition     = length(module.vpc_region_0) == 1
    error_message = "module.vpc_region_0 should be instantiated when byo_vpc = false"
  }

  assert {
    condition     = length(module.vpc_region_1) == 1
    error_message = "module.vpc_region_1 should be instantiated when byo_vpc = false"
  }
}
