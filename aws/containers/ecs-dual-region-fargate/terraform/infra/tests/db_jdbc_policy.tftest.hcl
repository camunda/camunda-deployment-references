# JDBC wrapper policy tests for terraform/infra/.
#
# The efm2 plugin and the 1 min failoverTimeoutMs are architectural choices of
# this reference architecture, not defaults on db_extra_wrapper_plugins /
# db_extra_url_parameters. These runs pin that: an operator extending either
# input adds to the policy, and cannot drop it by omission.
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

run "efm2_and_failover_timeout_are_the_defaults" {
  command = plan

  assert {
    condition     = jsonencode(local.db_wrapper_plugins) == jsonencode(["efm2"])
    error_message = "The reference architecture should load efm2 on top of the module's built-in plugins"
  }

  assert {
    condition     = jsonencode(local.db_url_parameters) == jsonencode({ failoverTimeoutMs = "60000" })
    error_message = "The reference architecture should set a 1 min failoverTimeoutMs"
  }
}

run "extra_wrapper_plugins_extend_rather_than_replace_efm2" {
  command = plan

  variables {
    db_extra_wrapper_plugins = ["readWriteSplitting"]
  }

  assert {
    condition     = jsonencode(local.db_wrapper_plugins) == jsonencode(["efm2", "readWriteSplitting"])
    error_message = "Adding a plugin should not drop efm2, which the architecture overview advertises"
  }
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
