mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }
}

variables {
  prefix   = "test"
  vpc_id   = "vpc-0abc123"
  vpc_cidr = "10.0.0.0/16"
}

run "creates_secrets_key_by_default" {
  command = plan

  assert {
    condition     = length(aws_kms_key.secrets) == 1
    error_message = "a secrets key must be created when none is supplied"
  }
}

run "uses_supplied_secrets_key" {
  command = plan

  variables {
    secrets_kms_key_arn = "arn:aws:kms:eu-west-1:000000000000:key/abc"
  }

  assert {
    condition     = length(aws_kms_key.secrets) == 0 && output.secrets_kms_key_arn == "arn:aws:kms:eu-west-1:000000000000:key/abc"
    error_message = "a supplied key must be used as is"
  }
}

run "registry_credentials_are_optional" {
  command = plan

  assert {
    condition     = output.registry_credentials_arn == ""
    error_message = "no registry secret without credentials"
  }
}
