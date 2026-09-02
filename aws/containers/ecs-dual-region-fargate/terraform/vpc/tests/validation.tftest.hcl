# Validation tests for terraform/vpc/.
#
# Covers per-variable regex validation and the two cross-variable check blocks
# in byo.tf. Every test in this file uses expect_failures to assert a SPECIFIC
# validation rule fires — never a blanket failure, otherwise a regression that
# breaks the wrong thing would still pass.
#
# These tests use mock_provider so no AWS calls are made.
#
# Design note: to test validation rules without poisoning the plan with
# unrelated resource errors (e.g. empty CIDRs hitting TGW route validation),
# regex tests supply a complete valid BYO fixture and invalidate exactly one
# field. Check-block tests use the smallest input shape that fires the check.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

# Override AZ data sources so greenfield-mode tests have deterministic AZs.
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

# A complete, valid BYO fixture. Individual regex tests override one field
# at a time to invalidate it.
variables {
  cluster_name = "test-validation"

  byo_vpc                          = true
  region_0_vpc_id                  = "vpc-aaaaaaaa"
  region_0_vpc_cidr                = "10.50.0.0/16"
  region_0_private_subnet_ids      = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  region_0_public_subnet_ids       = ["subnet-aaa4aaaa", "subnet-aaa5aaaa", "subnet-aaa6aaaa"]
  region_0_private_route_table_ids = ["rtb-aaa1aaaa"]

  region_1_vpc_id                  = "vpc-bbbbbbbb"
  region_1_vpc_cidr                = "10.60.0.0/16"
  region_1_private_subnet_ids      = ["subnet-bbb1bbbb", "subnet-bbb2bbbb", "subnet-bbb3bbbb"]
  region_1_public_subnet_ids       = ["subnet-bbb4bbbb", "subnet-bbb5bbbb", "subnet-bbb6bbbb"]
  region_1_private_route_table_ids = ["rtb-bbb1bbbb"]
}

# ---------------------------- Cross-variable: check.byo_vpc_required_inputs ----------------------------

run "byo_vpc_required_inputs_fail_when_subnets_below_minimum" {
  command = plan

  variables {
    # Override two subnet lists to length 2 — below the required 3.
    region_0_private_subnet_ids = ["subnet-aaa1aaaa", "subnet-aaa2aaaa"]
    region_1_private_subnet_ids = ["subnet-bbb1bbbb", "subnet-bbb2bbbb"]
  }

  expect_failures = [
    check.byo_vpc_required_inputs,
  ]
}

# ---------------------------- Cross-variable: check.create_vpc_inputs_clean ----------------------------

run "create_vpc_inputs_clean_fail_when_stray_vpc_id" {
  command = plan

  variables {
    # Clear all BYO vars, then switch to greenfield, then set one stray VPC ID.
    byo_vpc                          = false
    region_0_vpc_id                  = "vpc-aaaaaaaa"
    region_0_vpc_cidr                = ""
    region_0_private_subnet_ids      = []
    region_0_public_subnet_ids       = []
    region_0_private_route_table_ids = []
    region_1_vpc_id                  = ""
    region_1_vpc_cidr                = ""
    region_1_private_subnet_ids      = []
    region_1_public_subnet_ids       = []
    region_1_private_route_table_ids = []
  }

  expect_failures = [
    check.create_vpc_inputs_clean,
  ]
}

run "create_vpc_inputs_clean_fail_when_stray_subnet_ids" {
  command = plan

  variables {
    byo_vpc                          = false
    region_0_vpc_id                  = ""
    region_0_vpc_cidr                = ""
    region_0_private_subnet_ids      = []
    region_0_public_subnet_ids       = []
    region_0_private_route_table_ids = []
    region_1_vpc_id                  = ""
    region_1_vpc_cidr                = ""
    region_1_private_subnet_ids      = ["subnet-bbb1bbbb", "subnet-bbb2bbbb", "subnet-bbb3bbbb"]
    region_1_public_subnet_ids       = []
    region_1_private_route_table_ids = []
  }

  expect_failures = [
    check.create_vpc_inputs_clean,
  ]
}

# ---------------------------- Per-variable regex validation ----------------------------

run "vpc_id_regex_rejects_malformed" {
  command = plan

  variables {
    region_0_vpc_id = "not-a-vpc-id"
  }

  expect_failures = [
    var.region_0_vpc_id,
  ]
}

run "subnet_id_regex_rejects_malformed" {
  command = plan

  variables {
    region_0_private_subnet_ids = ["subnet-aaa1aaaa", "bogus-subnet", "subnet-aaa3aaaa"]
  }

  expect_failures = [
    var.region_0_private_subnet_ids,
  ]
}

run "route_table_id_regex_rejects_malformed" {
  command = plan

  variables {
    region_0_private_route_table_ids = ["wrong-format"]
  }

  expect_failures = [
    var.region_0_private_route_table_ids,
  ]
}

run "cidr_validation_rejects_garbage" {
  command = plan

  variables {
    region_0_vpc_cidr = "not-a-cidr"
  }

  expect_failures = [
    var.region_0_vpc_cidr,
  ]
}

run "networking_mode_rejects_invalid" {
  command = plan

  variables {
    networking_mode = "magic_network"
  }

  expect_failures = [
    var.networking_mode,
  ]
}
