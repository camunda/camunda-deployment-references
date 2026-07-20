# vpc_consumption tests — asserts that infra/ correctly wires the vpc/ remote
# state outputs through to the resources that need them.
#
# Catches regressions where the local.vpc.* references break or get reshuffled.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

# Distinctive sentinel values let assertions pin down exact propagation.
override_data {
  target = data.terraform_remote_state.vpc
  values = {
    outputs = {
      region_0_vpc_id                  = "vpc-sentinel0"
      region_0_vpc_cidr                = "10.111.0.0/16"
      region_0_private_subnet_ids      = ["subnet-priv0a", "subnet-priv0b", "subnet-priv0c"]
      region_0_public_subnet_ids       = ["subnet-pub0a", "subnet-pub0b", "subnet-pub0c"]
      region_0_private_route_table_ids = ["rtb-priv0a"]
      region_1_vpc_id                  = "vpc-sentinel1"
      region_1_vpc_cidr                = "10.222.0.0/16"
      region_1_private_subnet_ids      = ["subnet-priv1a", "subnet-priv1b", "subnet-priv1c"]
      region_1_public_subnet_ids       = ["subnet-pub1a", "subnet-pub1b", "subnet-pub1c"]
      region_1_private_route_table_ids = ["rtb-priv1a"]
      networking_mode                  = "transit_gateway"
    }
  }
}

# AZ data sources are queried for each private subnet; override them so locals.region_*_azs are deterministic.
override_data {
  target = data.aws_subnet.region_0_private[0]
  values = {
    availability_zone = "us-east-1a"
  }
}
override_data {
  target = data.aws_subnet.region_0_private[1]
  values = {
    availability_zone = "us-east-1b"
  }
}
override_data {
  target = data.aws_subnet.region_0_private[2]
  values = {
    availability_zone = "us-east-1c"
  }
}
override_data {
  target = data.aws_subnet.region_1_private[0]
  values = {
    availability_zone = "us-east-2a"
  }
}
override_data {
  target = data.aws_subnet.region_1_private[1]
  values = {
    availability_zone = "us-east-2b"
  }
}
override_data {
  target = data.aws_subnet.region_1_private[2]
  values = {
    availability_zone = "us-east-2c"
  }
}

variables {
  cluster_name                 = "test-infra"
  terraform_backend_bucket     = "test-tf-state-bucket"
  terraform_backend_key_prefix = "aws/containers/ecs-dual-region-fargate/test-infra/"
}

run "outputs_re_export_stubbed_vpc_values" {
  command = plan

  # infra/ re-exports vpc data via its own outputs so app/ doesn't need a second remote_state read.
  # Asserting on those outputs catches regressions where the local.vpc.* references break.

  assert {
    condition     = output.vpc_region_0_id == "vpc-sentinel0"
    error_message = "vpc_region_0_id output should equal stubbed local.vpc.region_0_vpc_id"
  }

  assert {
    condition     = output.vpc_region_1_id == "vpc-sentinel1"
    error_message = "vpc_region_1_id output should equal stubbed local.vpc.region_1_vpc_id"
  }

  assert {
    condition     = output.vpc_region_0_private_subnets == ["subnet-priv0a", "subnet-priv0b", "subnet-priv0c"]
    error_message = "vpc_region_0_private_subnets output should equal stubbed region_0_private_subnet_ids"
  }

  assert {
    condition     = output.vpc_region_1_private_subnets == ["subnet-priv1a", "subnet-priv1b", "subnet-priv1c"]
    error_message = "vpc_region_1_private_subnets output should equal stubbed region_1_private_subnet_ids"
  }
}

run "alb_consumes_public_subnets" {
  command = plan

  # aws_lb.subnets is a set — use setunion/length to compare without type-coercion issues.
  assert {
    condition     = length(setsubtract(aws_lb.alb_region_0.subnets, toset(["subnet-pub0a", "subnet-pub0b", "subnet-pub0c"]))) == 0 && length(aws_lb.alb_region_0.subnets) == 3
    error_message = "ALB region 0 should use the stubbed region_0_public_subnet_ids"
  }

  assert {
    condition     = length(setsubtract(aws_lb.alb_region_1.subnets, toset(["subnet-pub1a", "subnet-pub1b", "subnet-pub1c"]))) == 0 && length(aws_lb.alb_region_1.subnets) == 3
    error_message = "ALB region 1 should use the stubbed region_1_public_subnet_ids"
  }
}

run "azs_derived_from_subnets" {
  command = plan

  assert {
    condition     = length(local.region_0_azs) == 3 && contains(local.region_0_azs, "us-east-1a") && contains(local.region_0_azs, "us-east-1b") && contains(local.region_0_azs, "us-east-1c")
    error_message = "local.region_0_azs should be derived from the stubbed subnet AZs (region 0)"
  }

  assert {
    condition     = length(local.region_1_azs) == 3 && contains(local.region_1_azs, "us-east-2a") && contains(local.region_1_azs, "us-east-2b") && contains(local.region_1_azs, "us-east-2c")
    error_message = "local.region_1_azs should be derived from the stubbed subnet AZs (region 1)"
  }
}
