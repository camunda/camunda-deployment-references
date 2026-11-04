mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-1a", "eu-west-1b", "eu-west-1c", "eu-west-1d"]
    }
  }
}

run "byo_passes_ids_through" {
  command = plan

  variables {
    byo_vpc            = true
    vpc_id             = "vpc-0abc123"
    vpc_cidr           = "10.1.0.0/16"
    private_subnet_ids = ["subnet-a1", "subnet-b2", "subnet-c3"]
    public_subnet_ids  = ["subnet-d4", "subnet-e5", "subnet-f6"]
  }

  assert {
    condition     = output.vpc_id == "vpc-0abc123" && length(output.private_subnet_ids) == 3
    error_message = "BYO inputs must be exposed unchanged"
  }
}

run "byo_requires_three_private_subnets" {
  command = plan

  variables {
    byo_vpc            = true
    vpc_id             = "vpc-0abc123"
    vpc_cidr           = "10.1.0.0/16"
    private_subnet_ids = ["subnet-a1"]
  }

  expect_failures = [check.byo_vpc_required_inputs]
}

run "greenfield_rejects_leaked_byo_inputs" {
  command = plan

  variables {
    vpc_id = "vpc-0abc123"
  }

  expect_failures = [check.create_vpc_inputs_clean]
}

run "az_count_below_three_rejected" {
  command = plan

  variables {
    az_count = 2
  }

  expect_failures = [var.az_count]
}
