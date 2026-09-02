# IAM tests — branching behavior of the ECS task secrets policy.
#
# The policy must include the registry-credentials Secrets Manager ARN only
# when var.registry_username is non-empty. Catches regressions where the
# concat() expression drops a branch.

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
  cluster_name                 = "test-iam"
  terraform_backend_bucket     = "test-tf-state-bucket"
  terraform_backend_key_prefix = "aws/containers/ecs-dual-region-fargate/test-iam/"
}

run "registry_credentials_secret_created_when_username_supplied" {
  command = plan

  variables {
    registry_username = "ci-test-user"
    registry_password = "ci-test-pass"
  }

  assert {
    condition     = length(aws_secretsmanager_secret.registry_credentials_region_0) == 1
    error_message = "registry_credentials_region_0 secret should exist when registry_username is set"
  }

  assert {
    condition     = length(aws_secretsmanager_secret.registry_credentials_region_1) == 1
    error_message = "registry_credentials_region_1 secret should exist when registry_username is set"
  }
}

run "registry_credentials_secret_absent_when_username_empty" {
  command = plan

  variables {
    # Explicit empty override — run-block variable scope didn't reset us to the default after the previous run.
    registry_username = ""
    registry_password = ""
  }

  assert {
    condition     = length(aws_secretsmanager_secret.registry_credentials_region_0) == 0
    error_message = "registry_credentials_region_0 secret should NOT exist when registry_username is empty"
  }

  assert {
    condition     = length(aws_secretsmanager_secret.registry_credentials_region_1) == 0
    error_message = "registry_credentials_region_1 secret should NOT exist when registry_username is empty"
  }
}
