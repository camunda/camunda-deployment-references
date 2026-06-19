# Validation tests for terraform/infra/.
#
# infra/ has fewer validation rules than vpc/ because most networking-shaped
# validation moved to vpc/. The only thing left is secondary_storage_type.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

# Stub the vpc/ remote state so plan doesn't fail on missing state file.
override_data {
  target = data.terraform_remote_state.vpc
  values = {
    outputs = {
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
      networking_mode                  = "transit_gateway"
    }
  }
}

variables {
  cluster_name = "test-infra"
}

run "secondary_storage_type_rejects_invalid" {
  command = plan

  variables {
    secondary_storage_type = "magic_storage"
  }

  expect_failures = [
    var.secondary_storage_type,
  ]
}
