# Engine-selection tests for terraform/infra/.
#
# db_engine chooses the Aurora engine (PostgreSQL default, or MySQL) and drives
# the derived port, security-group rules, DB seed task, and re-exported outputs.

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

run "default_engine_is_postgresql" {
  command = plan

  assert {
    condition     = local.aurora_engine == "aurora-postgresql"
    error_message = "Default db_engine should map to aurora-postgresql"
  }

  assert {
    condition     = local.db_port == 5432
    error_message = "PostgreSQL db_port should be 5432"
  }
}

run "mysql_engine_selected" {
  command = plan

  variables {
    db_engine = "mysql"
  }

  assert {
    condition     = local.aurora_engine == "aurora-mysql"
    error_message = "db_engine=mysql should map to aurora-mysql"
  }

  assert {
    condition     = local.db_port == 3306
    error_message = "MySQL db_port should be 3306"
  }
}

run "invalid_db_engine_rejected" {
  command = plan

  variables {
    db_engine = "oracle"
  }

  expect_failures = [
    var.db_engine,
  ]
}

run "postgresql_cross_region_sg_uses_5432" {
  command = plan

  assert {
    condition     = anytrue([for r in aws_security_group.camunda_ports_region_0.egress : r.from_port == 5432 && r.to_port == 5432])
    error_message = "Region 0 cross-region Aurora egress should use 5432 for PostgreSQL"
  }

  assert {
    condition     = anytrue([for r in aws_security_group.camunda_ports_region_1.egress : r.from_port == 5432 && r.to_port == 5432])
    error_message = "Region 1 cross-region Aurora egress should use 5432 for PostgreSQL"
  }
}

run "mysql_cross_region_sg_uses_3306" {
  command = plan

  variables {
    db_engine = "mysql"
  }

  assert {
    condition     = anytrue([for r in aws_security_group.camunda_ports_region_0.egress : r.from_port == 3306 && r.to_port == 3306])
    error_message = "Region 0 cross-region Aurora egress should use 3306 for MySQL"
  }

  assert {
    condition     = anytrue([for r in aws_security_group.camunda_ports_region_1.egress : r.from_port == 3306 && r.to_port == 3306])
    error_message = "Region 1 cross-region Aurora egress should use 3306 for MySQL"
  }
}
