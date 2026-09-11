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

# Override the computed regional/global endpoints with deterministic, RDS-shaped
# values so jdbc_url is known at plan time and stable between runs. Values are
# chosen to not contain the substring "iam". File-level overrides apply to every
# run; `override_during = plan` is what makes them take effect for the
# `command = plan` runs, which is all of them.
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
    condition     = aws_rds_cluster.primary.engine_version == "18.4"
    error_message = "PostgreSQL engine_version should default to postgresql_engine_version (18.4)"
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

run "per_engine_version_variable_pins_that_engine" {
  command = plan

  variables {
    engine               = "aurora-mysql"
    mysql_engine_version = "8.4.mysql_aurora.8.4.99"
  }

  assert {
    condition     = aws_rds_cluster.primary.engine_version == "8.4.mysql_aurora.8.4.99"
    error_message = "Setting mysql_engine_version should pin the version on the MySQL path"
  }
}

run "per_engine_versions_do_not_leak_across_engines" {
  command = plan

  # Overriding the inactive engine's variable must not affect the selected one.
  variables {
    engine               = "aurora-postgresql"
    mysql_engine_version = "8.4.mysql_aurora.8.4.99"
  }

  assert {
    condition     = aws_rds_cluster.primary.engine_version == "18.4"
    error_message = "mysql_engine_version must not affect the PostgreSQL path"
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

  assert {
    condition     = strcontains(output.jdbc_url, "jdbc:aws-wrapper:postgresql://")
    error_message = "PostgreSQL jdbc_url should use the aws-wrapper:postgresql:// subprotocol"
  }

  assert {
    condition     = strcontains(output.jdbc_url, "sslmode=require")
    error_message = "PostgreSQL jdbc_url should pin sslmode=require rather than relying on the pgjdbc default"
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
    condition     = strcontains(output.jdbc_url_parameters["globalClusterInstanceHostPatterns"], "?.abc123def.us-east-1.rds.amazonaws.com")
    error_message = "globalClusterInstanceHostPatterns should strip the primary cluster id + .cluster- prefix"
  }

  assert {
    condition     = strcontains(output.jdbc_url_parameters["globalClusterInstanceHostPatterns"], "?.xyz789ghi.us-east-2.rds.amazonaws.com")
    error_message = "globalClusterInstanceHostPatterns should strip the secondary cluster id + .cluster- prefix"
  }
}

run "mysql_jdbc_url_uses_mysql_subprotocol_and_port" {
  command = plan

  variables {
    engine = "aurora-mysql"
  }

  assert {
    condition     = strcontains(output.jdbc_url, "jdbc:aws-wrapper:mysql://")
    error_message = "MySQL jdbc_url should use the aws-wrapper:mysql:// subprotocol"
  }

  assert {
    condition     = strcontains(output.jdbc_url, "sslMode=REQUIRED")
    error_message = "MySQL jdbc_url should pin sslMode=REQUIRED rather than relying on the Connector/J default"
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

  assert {
    condition     = strcontains(output.jdbc_url, "wrapperPlugins=initialConnection,iam,failover")
    error_message = "jdbc_url should include the iam plugin when iam_auth_enabled is true (default)"
  }

  # The wrapper's endpoint-compatibility matrix marks iam on an Aurora Global
  # Database endpoint as requiring initialConnection; without it the plugin
  # cannot resolve the instance it is signing a token for.
  assert {
    condition     = output.jdbc_url_parameters["wrapperPlugins"] == "initialConnection,iam,failover"
    error_message = "IAM auth must bring the initialConnection plugin with it on a global endpoint"
  }
}

run "extra_wrapper_plugins_are_appended" {
  command = plan

  variables {
    extra_wrapper_plugins = ["efm2", "readWriteSplitting"]
  }

  assert {
    condition     = strcontains(output.jdbc_url, "wrapperPlugins=initialConnection,iam,failover,efm2,readWriteSplitting")
    error_message = "extra_wrapper_plugins should be appended after the built-in iam,failover plugins, in order"
  }
}

run "extra_wrapper_plugins_do_not_duplicate_builtins" {
  command = plan

  variables {
    extra_wrapper_plugins = ["failover", "efm2"]
  }

  assert {
    condition     = strcontains(output.jdbc_url, "wrapperPlugins=initialConnection,iam,failover,efm2")
    error_message = "A plugin already provided by the module should not be repeated in wrapperPlugins"
  }
}

run "jdbc_component_outputs_compose_the_same_url" {
  command = plan

  # Assembling the components must reproduce the deprecated jdbc_url exactly, so
  # a consumer can migrate off it without changing the resulting connection.
  # Note the single rendering loop: no output carries a separator of its own.
  assert {
    condition = output.jdbc_url == join("", [
      "jdbc:aws-wrapper:",
      output.jdbc_subprotocol,
      "://",
      output.global_cluster_endpoint,
      ":",
      tostring(output.db_port),
      "/",
      output.database_name,
      "?",
      join("&", [for k, v in output.jdbc_url_parameters : "${k}=${v}"]),
    ])
    error_message = "The component outputs must compose to exactly the deprecated jdbc_url"
  }

  assert {
    condition     = output.jdbc_subprotocol == "postgresql" && output.jdbc_url_parameters["sslmode"] == "require"
    error_message = "PostgreSQL components should expose the postgresql subprotocol and sslmode=require"
  }

  # The TLS key is engine-specific, and only the engine's own spelling appears.
  assert {
    condition     = !contains(keys(output.jdbc_url_parameters), "sslMode")
    error_message = "The PostgreSQL parameter map should not carry the Connector/J spelling of the TLS key"
  }
}

run "engine_version_is_rejected_with_a_pointer_to_the_replacements" {
  command = plan

  # The input was removed in favour of the per-engine pins. It stays declared so
  # a consumer that still sets it is told what to use instead.
  variables {
    engine_version = "18.4"
  }

  expect_failures = [
    var.engine_version,
  ]
}

run "extra_url_parameters_reject_reserved_keys_in_any_case" {
  command = plan

  # The reserved list is a closed set of exact strings, so the guard folds case
  # before comparing; otherwise this variant reaches the query string.
  variables {
    extra_url_parameters = {
      SSLMODE = "disable"
    }
  }

  expect_failures = [
    var.extra_url_parameters,
  ]
}

run "extra_wrapper_plugins_reject_comma_separated_input" {
  command = plan

  variables {
    extra_wrapper_plugins = ["efm2,readWriteSplitting"]
  }

  expect_failures = [
    var.extra_wrapper_plugins,
  ]
}

run "jdbc_url_omits_iam_plugin_when_iam_disabled" {
  command = plan

  variables {
    iam_auth_enabled = false
  }

  assert {
    condition     = strcontains(output.jdbc_url, "wrapperPlugins=failover")
    error_message = "jdbc_url should omit the iam plugin when iam_auth_enabled = false"
  }

  assert {
    condition     = !strcontains(output.jdbc_url, "iam")
    error_message = "jdbc_url should not include the iam plugin when iam_auth_enabled = false"
  }
}

run "extra_url_parameters_are_appended" {
  command = plan

  variables {
    extra_url_parameters = {
      failureDetectionTime = "15000"
      connectTimeout       = "5000"
    }
  }

  assert {
    condition     = strcontains(output.jdbc_url, "?connectTimeout=5000&failureDetectionTime=15000&")
    error_message = "extra_url_parameters should be rendered into the jdbc_url, key-sorted with the rest"
  }

  # Merged into the one map rather than concatenated after it, so each parameter
  # appears exactly once and the module-owned entries are still present.
  assert {
    condition = alltrue([
      for k in ["wrapperPlugins", "globalClusterInstanceHostPatterns", "sslmode", "connectTimeout", "failureDetectionTime"] :
      contains(keys(output.jdbc_url_parameters), k)
    ])
    error_message = "Caller parameters must not displace the module-owned ones"
  }
}

run "extra_url_parameters_reject_module_owned_keys" {
  command = plan

  variables {
    extra_url_parameters = {
      wrapperPlugins = "none"
    }
  }

  expect_failures = [
    var.extra_url_parameters,
  ]
}

run "extra_url_parameters_reject_injection_in_values" {
  command = plan

  variables {
    extra_url_parameters = {
      connectTimeout = "5000&wrapperPlugins=none"
    }
  }

  expect_failures = [
    var.extra_url_parameters,
  ]
}

run "extra_url_parameters_accept_comma_separated_values" {
  command = plan

  variables {
    extra_url_parameters = {
      wrapperDialect = "aurora-pg"
      someList       = "a,b,c"
    }
  }

  assert {
    condition     = strcontains(output.jdbc_url, "someList=a,b,c")
    error_message = "A comma-separated value should be accepted and rendered verbatim"
  }
}

run "extra_url_parameters_reject_injection_in_keys" {
  command = plan

  variables {
    extra_url_parameters = {
      "connectTimeout=5000&wrapperPlugins" = "none"
    }
  }

  expect_failures = [
    var.extra_url_parameters,
  ]
}

run "failover_timeout_passes_through_extra_url_parameters" {
  command = plan

  variables {
    extra_url_parameters = {
      failoverTimeoutMs = "60000"
    }
  }

  assert {
    condition     = strcontains(output.jdbc_url, "failoverTimeoutMs=60000")
    error_message = "failoverTimeoutMs should be rendered into the jdbc_url when passed through extra_url_parameters"
  }
}
