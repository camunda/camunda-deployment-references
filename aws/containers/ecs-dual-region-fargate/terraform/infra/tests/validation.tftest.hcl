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
  cluster_name                 = "test-infra"
  terraform_backend_bucket     = "test-tf-state-bucket"
  terraform_backend_key_prefix = "aws/containers/ecs-dual-region-fargate/test-infra/"
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

run "mysql_rejects_a_username_longer_than_32_characters" {
  command = plan

  # MySQL stores account names in a char(32); this one plans fine against
  # PostgreSQL and would fail at CREATE USER during the seed task.
  variables {
    db_engine             = "mysql"
    db_seed_iam_usernames = ["camunda_user_with_a_very_long_name_x"]
  }

  expect_failures = [
    var.db_seed_iam_usernames,
  ]
}

run "postgresql_accepts_the_same_username" {
  command = plan

  # The same value is a valid PostgreSQL role name (63-character ceiling), so
  # the ceiling has to follow the engine rather than being fixed at the lower
  # of the two.
  variables {
    db_engine             = "postgresql"
    db_seed_iam_usernames = ["camunda_user_with_a_very_long_name_x"]
  }

  assert {
    condition     = length(var.db_seed_iam_usernames[0]) == 36
    error_message = "The fixture should be longer than MySQL's 32-character limit and within PostgreSQL's 63"
  }
}
