mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }
}

variables {
  prefix     = "test"
  aws_region = "eu-west-1"
}

run "one_lease_bucket_per_zone" {
  command = plan

  variables {
    zones = ["london", "paris"]
  }

  assert {
    condition     = length(module.lease) == 2
    error_message = "each zone needs its own lease bucket"
  }
}

run "invalid_zone_name_rejected" {
  command = plan

  variables {
    zones = ["bad_zone"]
  }

  expect_failures = [var.zones]
}
