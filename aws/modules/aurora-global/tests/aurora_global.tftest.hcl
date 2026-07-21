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

run "postgresql_engine_selects_default_version" {
  command = plan

  # engine defaults to aurora-postgresql
  assert {
    condition     = aws_rds_cluster.primary.engine == "aurora-postgresql"
    error_message = "Default engine should be aurora-postgresql"
  }

  assert {
    condition     = aws_rds_cluster.primary.engine_version == "18.3"
    error_message = "PostgreSQL engine_version should default to postgresql_engine_version (18.3)"
  }
}

run "mysql_engine_selects_default_version" {
  command = plan

  variables {
    engine = "aurora-mysql"
  }

  assert {
    condition     = aws_rds_cluster.primary.engine == "aurora-mysql"
    error_message = "engine should be aurora-mysql on the primary cluster"
  }

  assert {
    condition     = aws_rds_cluster.primary.engine_version == "8.4.mysql_aurora.8.4.7"
    error_message = "MySQL engine_version should default to mysql_engine_version (8.4.mysql_aurora.8.4.7)"
  }

  assert {
    condition     = aws_rds_cluster.secondary.engine == "aurora-mysql"
    error_message = "engine should be aurora-mysql on the secondary cluster"
  }
}

run "explicit_engine_version_override_wins" {
  command = plan

  variables {
    engine         = "aurora-mysql"
    engine_version = "8.4.99"
  }

  assert {
    condition     = aws_rds_cluster.primary.engine_version == "8.4.99"
    error_message = "Explicit engine_version should override the per-engine default"
  }
}

run "invalid_engine_rejected" {
  command = plan

  variables {
    engine = "aurora-invalid"
  }

  expect_failures = [
    var.engine,
  ]
}

run "postgresql_security_group_uses_5432" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_security_group.primary.ingress : r.from_port == 5432 && r.to_port == 5432])
    error_message = "PostgreSQL primary SG ingress should use port 5432"
  }

  assert {
    condition     = alltrue([for r in aws_security_group.primary.egress : r.from_port == 5432 && r.to_port == 5432])
    error_message = "PostgreSQL primary SG egress should use port 5432"
  }

  assert {
    condition     = alltrue([for r in aws_security_group.secondary.ingress : r.from_port == 5432 && r.to_port == 5432])
    error_message = "PostgreSQL secondary SG ingress should use port 5432"
  }

  assert {
    condition     = alltrue([for r in aws_security_group.secondary.egress : r.from_port == 5432 && r.to_port == 5432])
    error_message = "PostgreSQL secondary SG egress should use port 5432"
  }
}

run "mysql_security_group_uses_3306" {
  command = plan

  variables {
    engine = "aurora-mysql"
  }

  assert {
    condition     = alltrue([for r in aws_security_group.primary.ingress : r.from_port == 3306 && r.to_port == 3306])
    error_message = "MySQL primary SG ingress should use port 3306"
  }

  assert {
    condition     = alltrue([for r in aws_security_group.primary.egress : r.from_port == 3306 && r.to_port == 3306])
    error_message = "MySQL primary SG egress should use port 3306"
  }

  assert {
    condition     = alltrue([for r in aws_security_group.secondary.ingress : r.from_port == 3306 && r.to_port == 3306])
    error_message = "MySQL secondary SG ingress should use port 3306"
  }

  assert {
    condition     = alltrue([for r in aws_security_group.secondary.egress : r.from_port == 3306 && r.to_port == 3306])
    error_message = "MySQL secondary SG egress should use port 3306"
  }
}

run "postgresql_jdbc_url_uses_postgresql_subprotocol_and_port" {
  command = plan

  # Override the computed regional/global endpoints with deterministic,
  # RDS-shaped values so jdbc_url is known at plan time and stable between
  # runs. Values are chosen to not contain the substring "iam".
  override_resource {
    target          = aws_rds_global_cluster.this
    override_during = plan
    values = {
      endpoint = "test-global.cluster-abc123def.us-east-1.rds.amazonaws.com"
    }
  }
  override_resource {
    target          = aws_rds_cluster.primary
    override_during = plan
    values = {
      endpoint = "test-primary.cluster-abc123def.us-east-1.rds.amazonaws.com"
    }
  }
  override_resource {
    target          = aws_rds_cluster.secondary
    override_during = plan
    values = {
      endpoint = "test-secondary.cluster-xyz789ghi.us-east-2.rds.amazonaws.com"
    }
  }

  assert {
    condition     = strcontains(output.jdbc_url, "jdbc:aws-wrapper:postgresql://")
    error_message = "PostgreSQL jdbc_url should use the aws-wrapper:postgresql:// subprotocol"
  }

  assert {
    condition     = strcontains(output.jdbc_url, ":5432/")
    error_message = "PostgreSQL jdbc_url should use port 5432"
  }

  assert {
    condition     = output.db_port == 5432
    error_message = "PostgreSQL db_port output should be 5432"
  }

  assert {
    condition     = strcontains(output.jdbc_instance_host_patterns, "?.abc123def.us-east-1.rds.amazonaws.com")
    error_message = "jdbc_instance_host_patterns should strip the primary cluster id + .cluster- prefix"
  }

  assert {
    condition     = strcontains(output.jdbc_instance_host_patterns, "?.xyz789ghi.us-east-2.rds.amazonaws.com")
    error_message = "jdbc_instance_host_patterns should strip the secondary cluster id + .cluster- prefix"
  }
}

run "mysql_jdbc_url_uses_mysql_subprotocol_and_port" {
  command = plan

  variables {
    engine = "aurora-mysql"
  }

  override_resource {
    target          = aws_rds_global_cluster.this
    override_during = plan
    values = {
      endpoint = "test-global.cluster-abc123def.us-east-1.rds.amazonaws.com"
    }
  }
  override_resource {
    target          = aws_rds_cluster.primary
    override_during = plan
    values = {
      endpoint = "test-primary.cluster-abc123def.us-east-1.rds.amazonaws.com"
    }
  }
  override_resource {
    target          = aws_rds_cluster.secondary
    override_during = plan
    values = {
      endpoint = "test-secondary.cluster-xyz789ghi.us-east-2.rds.amazonaws.com"
    }
  }

  assert {
    condition     = strcontains(output.jdbc_url, "jdbc:aws-wrapper:mysql://")
    error_message = "MySQL jdbc_url should use the aws-wrapper:mysql:// subprotocol"
  }

  assert {
    condition     = strcontains(output.jdbc_url, ":3306/")
    error_message = "MySQL jdbc_url should use port 3306"
  }

  assert {
    condition     = output.db_port == 3306
    error_message = "MySQL db_port output should be 3306"
  }
}

run "jdbc_url_includes_iam_plugin_by_default" {
  command = plan

  override_resource {
    target          = aws_rds_global_cluster.this
    override_during = plan
    values = {
      endpoint = "test-global.cluster-abc123def.us-east-1.rds.amazonaws.com"
    }
  }
  override_resource {
    target          = aws_rds_cluster.primary
    override_during = plan
    values = {
      endpoint = "test-primary.cluster-abc123def.us-east-1.rds.amazonaws.com"
    }
  }
  override_resource {
    target          = aws_rds_cluster.secondary
    override_during = plan
    values = {
      endpoint = "test-secondary.cluster-xyz789ghi.us-east-2.rds.amazonaws.com"
    }
  }

  assert {
    condition     = strcontains(output.jdbc_url, "wrapperPlugins=iam,failover")
    error_message = "jdbc_url should include the iam plugin when iam_auth_enabled is true (default)"
  }
}

run "jdbc_url_omits_iam_plugin_when_iam_disabled" {
  command = plan

  variables {
    iam_auth_enabled = false
  }

  override_resource {
    target          = aws_rds_global_cluster.this
    override_during = plan
    values = {
      endpoint = "test-global.cluster-abc123def.us-east-1.rds.amazonaws.com"
    }
  }
  override_resource {
    target          = aws_rds_cluster.primary
    override_during = plan
    values = {
      endpoint = "test-primary.cluster-abc123def.us-east-1.rds.amazonaws.com"
    }
  }
  override_resource {
    target          = aws_rds_cluster.secondary
    override_during = plan
    values = {
      endpoint = "test-secondary.cluster-xyz789ghi.us-east-2.rds.amazonaws.com"
    }
  }

  assert {
    condition     = strcontains(output.jdbc_url, "wrapperPlugins=failover")
    error_message = "jdbc_url should omit the iam plugin when iam_auth_enabled = false"
  }

  assert {
    condition     = !strcontains(output.jdbc_url, "wrapperPlugins=iam")
    error_message = "jdbc_url should not include the iam plugin when iam_auth_enabled = false"
  }
}
