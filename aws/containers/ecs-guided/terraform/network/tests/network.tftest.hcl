mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    }
  }
}

variables {
  prefix = "test"
}

run "byo_vpc_skips_creation" {
  command = plan

  variables {
    byo_vpc            = true
    vpc_id             = "vpc-0abc123"
    vpc_cidr           = "10.1.0.0/16"
    private_subnet_ids = ["subnet-a1", "subnet-b2", "subnet-c3"]
  }

  assert {
    condition     = output.vpc_id == "vpc-0abc123"
    error_message = "a brought VPC must be exposed as is"
  }
}
