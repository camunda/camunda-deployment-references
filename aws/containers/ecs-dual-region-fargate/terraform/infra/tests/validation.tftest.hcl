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

run "ports_rejects_a_retired_database_port_entry" {
  command = plan

  # The shape a pre-existing override would have: the old default, carried
  # forward. Without this the entry still drives dynamic ingress and egress, so
  # a MySQL deployment would open 5432 alongside 3306.
  variables {
    ports = {
      camunda_web_ui = 8080
      postgresql     = 5432
    }
  }

  expect_failures = [
    var.ports,
  ]
}

run "opensearch_does_not_apply_the_mysql_username_ceiling" {
  command = plan

  # No seed task exists here and db_engine is inert, so a 36-character name —
  # rejected when the seed really does run against MySQL — must be accepted.
  variables {
    secondary_storage_type = "opensearch"
    db_engine              = "mysql"
    db_seed_iam_usernames  = ["camunda_user_with_a_very_long_name_x"]
  }

  assert {
    condition     = length(var.db_seed_iam_usernames[0]) > 32
    error_message = "The fixture must exceed MySQL's ceiling for this run to prove anything"
  }
}

run "mysql_rejects_an_admin_username_longer_than_16_characters" {
  command = plan

  # RDS caps an Aurora MySQL master username at 16 characters. Without this the
  # value plans clean and AWS rejects the cluster mid-apply.
  variables {
    db_engine         = "mysql"
    db_admin_username = "camunda_admin_user"
  }

  expect_failures = [
    var.db_admin_username,
  ]
}

run "postgresql_accepts_the_same_admin_username" {
  command = plan

  variables {
    db_engine         = "postgresql"
    db_admin_username = "camunda_admin_user"
  }

  assert {
    condition     = length(var.db_admin_username) > 16
    error_message = "The fixture must exceed MySQL's master-username limit for this run to prove anything"
  }
}

run "admin_username_rejects_whitespace" {
  command = plan

  # It is interpolated unquoted into the psql conninfo the seed task builds.
  variables {
    db_admin_username = "camunda admin"
  }

  expect_failures = [
    var.db_admin_username,
  ]
}
