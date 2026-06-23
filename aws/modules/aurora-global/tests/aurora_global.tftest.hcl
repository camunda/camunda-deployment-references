# Tests for the aurora-global module.
#
# The module declares two providers (aws.primary and aws.secondary). Mock both.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "primary"
}
mock_provider "aws" {
  alias = "secondary"
}

# Minimal valid fixture. Individual runs override specific fields.
variables {
  global_cluster_identifier  = "test-global"
  primary_cluster_name       = "test-primary"
  secondary_cluster_name     = "test-secondary"
  primary_vpc_id             = "vpc-aaaaaaaa"
  primary_subnet_ids         = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  primary_cidr_blocks        = ["10.50.0.0/16", "10.60.0.0/16"]
  primary_availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  secondary_vpc_id           = "vpc-bbbbbbbb"
  secondary_subnet_ids       = ["subnet-bbb1bbbb", "subnet-bbb2bbbb", "subnet-bbb3bbbb"]
  secondary_cidr_blocks      = ["10.50.0.0/16", "10.60.0.0/16"]
  master_username            = "camunda_admin"
  master_password            = "test-password-32-chars-long-ok!!"
}

run "default_primary_instance_count" {
  command = plan

  # primary_num_instances defaults to 1
  assert {
    condition     = length(aws_rds_cluster_instance.primary) == 1
    error_message = "Default primary_num_instances should produce 1 instance"
  }
}

run "multiple_primary_instances" {
  command = plan

  variables {
    primary_num_instances = 3
  }

  assert {
    condition     = length(aws_rds_cluster_instance.primary) == 3
    error_message = "primary_num_instances = 3 should produce 3 instances"
  }
}

run "secondary_instance_count_matches_var" {
  command = plan

  variables {
    secondary_num_instances = 2
  }

  assert {
    condition     = length(aws_rds_cluster_instance.secondary) == 2
    error_message = "secondary_num_instances = 2 should produce 2 instances"
  }
}

run "iam_auth_enabled_propagates_to_clusters" {
  command = plan

  # iam_auth_enabled defaults to true
  assert {
    condition     = aws_rds_cluster.primary.iam_database_authentication_enabled == true
    error_message = "Default iam_auth_enabled should be true on primary cluster"
  }

  assert {
    condition     = aws_rds_cluster.secondary.iam_database_authentication_enabled == true
    error_message = "Default iam_auth_enabled should be true on secondary cluster"
  }
}

run "iam_auth_disabled_propagates" {
  command = plan

  variables {
    iam_auth_enabled = false
  }

  assert {
    condition     = aws_rds_cluster.primary.iam_database_authentication_enabled == false
    error_message = "iam_auth_enabled = false should disable IAM auth on primary cluster"
  }
}

run "global_cluster_identifier_set" {
  command = plan

  assert {
    condition     = aws_rds_global_cluster.this.global_cluster_identifier == "test-global"
    error_message = "global_cluster_identifier should match var input"
  }
}
