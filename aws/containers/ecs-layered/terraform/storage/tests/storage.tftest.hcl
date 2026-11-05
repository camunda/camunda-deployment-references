mock_provider "aws" {
  mock_data "aws_subnet" {
    defaults = {
      availability_zone = "eu-west-1a"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::000000000000:policy/mock"
    }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      cluster_resource_id = "cluster-ABC"
      endpoint            = "db.example"
      port                = 5432
    }
  }
}
mock_provider "random" {}
mock_provider "null" {}

variables {
  prefix                   = "test"
  vpc_id                   = "vpc-0abc123"
  vpc_cidr                 = "10.0.0.0/16"
  private_subnet_ids       = ["subnet-a1", "subnet-b2", "subnet-c3"]
  ecs_cluster_arn          = "arn:aws:ecs:eu-west-1:000000000000:cluster/test"
  task_execution_role_arn  = "arn:aws:iam::000000000000:role/exec"
  task_execution_role_name = "exec"
  secrets_kms_key_arn      = "arn:aws:kms:eu-west-1:000000000000:key/abc"
  seed_security_group_ids  = ["sg-ports"]
}

run "standalone_by_default" {
  command = plan

  assert {
    condition     = var.global_cluster_identifier == null
    error_message = "the cluster starts standalone"
  }
}

run "one_connect_policy_per_iam_user" {
  command = plan

  variables {
    db_seed_iam_usernames = ["camunda", "other"]
  }

  assert {
    condition     = length(aws_iam_policy.rds_db_connect) == 2
    error_message = "each IAM database user needs a connect policy"
  }
}

run "iam_auth_is_required" {
  command = plan

  variables {
    db_iam_auth_enabled = false
  }

  expect_failures = [var.db_iam_auth_enabled]
}

run "further_databases_get_roles_and_policies" {
  command = plan

  variables {
    databases = {
      hub      = { database_name = "camunda_hub", username = "camunda_hub" }
      provider = { database_name = "oidc_provider", username = "oidc_provider", auth = "password" }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.database) == 1 && contains(keys(aws_iam_policy.rds_db_connect), "camunda_hub")
    error_message = "a password database gets a secret, an IAM database gets a connect policy"
  }
}

run "unsafe_database_names_rejected" {
  command = plan

  variables {
    databases = {
      bad = { database_name = "x\"; DROP", username = "x" }
    }
  }

  expect_failures = [var.databases]
}
