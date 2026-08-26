################################
# Engine-derived values       #
################################

locals {
  # Protocol port is fixed per engine (derived, not a variable, to prevent a
  # port/engine mismatch). Consumed by the security groups and the jdbc_url
  # output. Consumers that must know the port without instantiating this module
  # (e.g. security groups created unconditionally) should mirror this map and
  # reference it — see aws/containers/ecs-dual-region-fargate/terraform/infra.
  engine_ports = {
    "aurora-postgresql" = 5432
    "aurora-mysql"      = 3306
  }
  db_port = local.engine_ports[var.engine]

  # Per-engine default version comes from the Renovate-tracked variables.
  default_engine_versions = {
    "aurora-postgresql" = var.postgresql_engine_version
    "aurora-mysql"      = var.mysql_engine_version
  }
  engine_version = coalesce(var.engine_version, local.default_engine_versions[var.engine])

  # Human-readable label for security-group rule descriptions. A map (not a
  # ternary) so an unhandled engine fails fast, matching the engine_ports /
  # default_engine_versions / jdbc_subprotocols lookups.
  family_labels = {
    "aurora-postgresql" = "PostgreSQL"
    "aurora-mysql"      = "MySQL"
  }
  family_label = local.family_labels[var.engine]
}

################################################################
#          JDBC URL (AWS Advanced JDBC Wrapper)                #
################################################################

locals {
  jdbc_subprotocols = {
    "aurora-postgresql" = "postgresql"
    "aurora-mysql"      = "mysql"
  }
  jdbc_subprotocol = local.jdbc_subprotocols[var.engine]

  # AWS Advanced JDBC Wrapper global-cluster instance host patterns (failover
  # plugin). "?." matches any instance in a regional cluster; derived by
  # stripping the cluster id + ".cluster-" from each regional endpoint.
  jdbc_primary_host_pattern   = "?.${replace(aws_rds_cluster.primary.endpoint, "${aws_rds_cluster.primary.cluster_identifier}.cluster-", "")}"
  jdbc_secondary_host_pattern = "?.${replace(aws_rds_cluster.secondary.endpoint, "${aws_rds_cluster.secondary.cluster_identifier}.cluster-", "")}"
  jdbc_instance_host_patterns = "${local.jdbc_primary_host_pattern},${local.jdbc_secondary_host_pattern}"

  # iam plugin only when IAM auth is enabled; failover always (global cluster).
  # var.extra_wrapper_plugins is appended after the built-ins; distinct() keeps
  # the result stable if a caller repeats one of them.
  jdbc_base_wrapper_plugins = var.iam_auth_enabled ? ["iam", "failover"] : ["failover"]
  jdbc_wrapper_plugins      = join(",", distinct(concat(local.jdbc_base_wrapper_plugins, var.extra_wrapper_plugins)))

  # TLS is pinned explicitly rather than left to the driver default: pgjdbc
  # defaults to sslmode=prefer and Connector/J to sslMode=PREFERRED, both of
  # which permit a silent plaintext downgrade. With IAM authentication the
  # credential on the wire is a signed bearer token, so encryption should not
  # depend on a negotiated default.
  jdbc_ssl_params = {
    "aurora-postgresql" = "&sslmode=require"
    "aurora-mysql"      = "&sslMode=REQUIRED"
  }

  # Caller-supplied parameters come last; a validation on the variable keeps
  # them from shadowing the module-owned ones (the failover plugin's own
  # settings included — those are typed inputs). Map iteration is key-sorted,
  # so the generated URL is stable across plans.
  jdbc_extra_url_parameters = join("", [for k, v in var.extra_url_parameters : "&${k}=${v}"])

  jdbc_url = "jdbc:aws-wrapper:${local.jdbc_subprotocol}://${aws_rds_global_cluster.this.endpoint}:${local.db_port}/${var.database_name}?wrapperPlugins=${local.jdbc_wrapper_plugins}&globalClusterInstanceHostPatterns=${local.jdbc_instance_host_patterns}&failoverTimeoutMs=${var.failover_timeout_ms}${local.jdbc_ssl_params[var.engine]}${local.jdbc_extra_url_parameters}"
}
