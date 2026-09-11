# JDBC wrapper policy tests for terraform/infra/.
#
# The 1 min failoverTimeoutMs is an architectural choice of this reference
# architecture, not a default on db_extra_url_parameters. These runs pin that:
# an operator extending the input adds to the policy and cannot drop it by
# omission. They also pin that IAM auth cannot be turned off, since nothing
# supplies a database password in its place.
#
# Comparisons go through jsonencode: a map(string) local and an HCL object
# literal are different types to `==`, and jsonencode sorts object keys, so
# this compares contents without depending on the literal's ordering.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

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

run "failover_timeout_is_the_default" {
  command = plan

  assert {
    condition     = jsonencode(local.db_url_parameters) == jsonencode({ failoverTimeoutMs = "60000" })
    error_message = "The reference architecture should set a 1 min failoverTimeoutMs"
  }
}

run "iam_auth_cannot_be_disabled_for_rdbms" {
  command = plan

  # The seed creates the Camunda user with the IAM auth plugin and no password,
  # and the task definition wires no password secret, so a cluster built with
  # this off cannot be connected to. Fail at plan time rather than at runtime.
  variables {
    db_iam_auth_enabled = false
  }

  expect_failures = [
    var.db_iam_auth_enabled,
  ]
}

run "extra_url_parameters_extend_rather_than_replace_the_timeout" {
  command = plan

  variables {
    db_extra_url_parameters = {
      failureDetectionTime = "15000"
    }
  }

  assert {
    condition = jsonencode(local.db_url_parameters) == jsonencode({
      failoverTimeoutMs    = "60000"
      failureDetectionTime = "15000"
    })
    error_message = "Adding a URL parameter should not drop the architecture's failoverTimeoutMs"
  }
}

run "extra_url_parameters_can_retune_the_timeout" {
  command = plan

  variables {
    db_extra_url_parameters = {
      failoverTimeoutMs = "30000"
    }
  }

  assert {
    condition     = jsonencode(local.db_url_parameters) == jsonencode({ failoverTimeoutMs = "30000" })
    error_message = "An explicit failoverTimeoutMs should win over the architecture's default"
  }
}
