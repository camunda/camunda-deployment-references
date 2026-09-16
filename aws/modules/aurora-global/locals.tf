################################
# Engine-derived values       #
################################

locals {
  # Protocol port is fixed per engine (derived, not a variable, to prevent a
  # port/engine mismatch). Consumed by the security groups and the db_port
  # output. Consumers that must know the port without instantiating this module
  # (e.g. security groups created unconditionally) should mirror this map and
  # reference it — see aws/containers/ecs-dual-region-fargate/terraform/infra.
  engine_ports = {
    "aurora-postgresql" = 5432
    "aurora-mysql"      = 3306
  }
  db_port = local.engine_ports[var.engine]

  # One version variable per engine, each independently Renovate-tracked (the
  # two engines resolve through different custom datasources). Selecting by
  # engine here means there is exactly one way to pin a version: set that
  # engine's variable.
  engine_versions = {
    "aurora-postgresql" = var.postgresql_engine_version
    "aurora-mysql"      = var.mysql_engine_version
  }
  engine_version = local.engine_versions[var.engine]

  # Human-readable label for security-group rule descriptions. A map (not a
  # ternary) so an unhandled engine fails fast, matching the engine_ports /
  # engine_versions / jdbc_subprotocols lookups.
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

  # failover and initialConnection always; iam only when IAM auth is enabled.
  #
  # initialConnection is unconditional on purpose. The wrapper's
  # endpoint-compatibility matrix marks both iam *and* efm/efm2 on an Aurora
  # Global Database endpoint — the endpoint this URL targets — as "requires
  # initialConnection", because those plugins must resolve the global endpoint
  # to the instance they are really talking to. Making it conditional on
  # iam_auth_enabled would mean a caller adding efm2 through
  # extra_wrapper_plugins with IAM off got a silently non-functional plugin,
  # and the constraint would live only in prose. Including it always costs
  # nothing — it is a connection-strategy plugin the wrapper recommends for
  # cluster and global endpoints regardless.
  #
  # var.extra_wrapper_plugins is appended after the built-ins; distinct() keeps
  # the result stable if a caller repeats one of them. The position a plugin
  # takes here is not its execution order: the wrapper re-sorts the pipeline by
  # built-in weight unless autoSortWrapperPluginOrder is turned off.
  jdbc_base_wrapper_plugins = concat(
    ["initialConnection"],
    var.iam_auth_enabled ? ["iam"] : [],
    ["failover"],
  )
  jdbc_wrapper_plugins = join(",", distinct(concat(local.jdbc_base_wrapper_plugins, var.extra_wrapper_plugins)))

  # TLS is pinned explicitly rather than left to the driver default: pgjdbc
  # defaults to sslmode=prefer and Connector/J to sslMode=PREFERRED, both of
  # which permit a silent plaintext downgrade. With IAM authentication the
  # credential on the wire is a signed bearer token, so encryption should not
  # depend on a negotiated default.
  # Note what this does and does not buy: require/REQUIRED force encryption but
  # do *not* verify the server certificate, so they stop a passive eavesdropper
  # and not an active man-in-the-middle. Raising it to verify-full (pgjdbc) or
  # VERIFY_IDENTITY (Connector/J) needs a CA bundle on the client, which this
  # reference architecture does not ship — so the default is the strongest mode
  # that works everywhere, and extra_url_parameters deliberately *allows* the
  # key so a deployment with a trust store can harden it. Only weakening is
  # rejected.
  jdbc_ssl_parameters = {
    "aurora-postgresql" = { sslmode = "require" }
    "aurora-mysql"      = { sslMode = "REQUIRED" }
  }

  # Every query parameter in one map, module-owned entries first and caller
  # parameters merged over them. One map rather than a component per parameter
  # so that no output owns a leading '&' and a consumer renders the whole set
  # with a single loop; the alternative had callers knowing, per output, whether
  # it carried its own separator.
  #
  # Validations on extra_url_parameters reject the module-owned keys (in any
  # capitalisation) and any key or value containing '&' or '=', so merging last
  # cannot shadow an entry above or smuggle in a parameter of its own. Plugin
  # parameters (failoverTimeoutMs, failureDetectionTime, ...) travel through
  # there rather than as typed inputs: the module builds the plugin list, not
  # the plugins' configuration, and defaulting them would vendor the driver's
  # own defaults.
  jdbc_url_parameters = merge(
    {
      wrapperPlugins                    = local.jdbc_wrapper_plugins
      globalClusterInstanceHostPatterns = local.jdbc_instance_host_patterns
    },
    local.jdbc_ssl_parameters[var.engine],
    var.extra_url_parameters,
  )

}
