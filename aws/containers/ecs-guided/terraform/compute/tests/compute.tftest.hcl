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

run "peered_cidrs_are_allowed_on_the_camunda_ports" {
  command = plan

  variables {
    additional_cidr_blocks = ["10.191.0.0/16"]
  }

  assert {
    condition     = alltrue([for r in aws_security_group.camunda_ports_within_vpc.ingress : contains(r.cidr_blocks, "10.191.0.0/16") if r.from_port != 2049])
    error_message = "the other region's CIDR must be allowed wherever the VPC's own is"
  }
}

run "management_plane_ports_are_closed_by_default" {
  command = plan

  assert {
    condition     = !anytrue([for r in aws_security_group.camunda_ports_within_vpc.ingress : r.from_port == 8084])
    error_message = "management plane ports are opened only on demand"
  }
}

run "management_plane_ports_open_on_demand" {
  command = plan

  variables {
    enable_management_plane = true
  }

  assert {
    condition     = anytrue([for r in aws_security_group.camunda_ports_within_vpc.ingress : r.from_port == 8084])
    error_message = "enable_management_plane must open the Management Identity port"
  }
}
