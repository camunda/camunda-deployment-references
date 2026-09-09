################################
# Computed Values             #
################################

locals {
  # Zeebe dual-region cluster configuration
  cluster_size        = 8
  replication_factor  = 4
  partition_count     = 8
  brokers_per_region  = 4
  replicas_per_region = local.replication_factor / 2

  # Region-aware partitioning env vars
  # Note: CAMUNDA_CLUSTER_SIZE, REPLICATIONFACTOR, PARTITIONCOUNT, and INITIALCONTACTPOINTS
  # are already set by the orchestration-cluster module via its variables.
  partitioning_env_vars = [
    {
      name  = "CAMUNDA_CLUSTER_NAME"
      value = local.infra.cluster_name
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_SCHEME"
      value = "ZONE_AWARE"
    },
    # Increase SWIM probe timeout for cross-region latency (default 100ms is too tight for Transit Gateway)
    {
      name  = "ZEEBE_BROKER_CLUSTER_MEMBERSHIP_PROBETIMEOUT"
      value = "1000ms"
    },
    {
      name  = "ZEEBE_BROKER_CLUSTER_MEMBERSHIP_FAILURETIMEOUT"
      value = "10000ms"
    },
    # Region 0 topology
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_0_NAME"
      value = local.infra.region_0
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_0_NUMBEROFREPLICAS"
      value = tostring(local.replicas_per_region)
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_0_NUMBEROFBROKERS"
      value = tostring(local.brokers_per_region)
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_0_PRIORITY"
      value = "1000"
    },
    # Region 1 topology
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_1_NAME"
      value = local.infra.region_1
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_1_NUMBEROFREPLICAS"
      value = tostring(local.replicas_per_region)
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_1_NUMBEROFBROKERS"
      value = tostring(local.brokers_per_region)
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_1_PRIORITY"
      value = "500"
    },
    # enable async replication in zeebe to avoid data loss on failover.
    # reference: https://docs.camunda.io/docs/self-managed/concepts/databases/relational-db/database-configuration/#multi-region-support
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_ENABLED"
      value = "true"
    },
  ]

  # Region-specific: tells each broker which region it belongs to
  cluster_region_env_region_0 = [
    {
      name  = "CAMUNDA_CLUSTER_ZONE"
      value = local.infra.region_0
    },
  ]

  cluster_region_env_region_1 = [
    {
      name  = "CAMUNDA_CLUSTER_ZONE"
      value = local.infra.region_1
    },
  ]

  # JDBC URL for RDBMS secondary storage, assembled here rather than in the infra
  # layer: a connection property (timeout, pool setting, an extra wrapper
  # property) is an application concern, and changing one should not require
  # re-applying the infrastructure state. The infra layer supplies only the
  # engine-derived components.
  #
  # Precedence: var.rdbms_jdbc_url (full override) > var.rdbms_extra_jdbc_params
  # > the parameters and components the infra layer supplies. A full override is
  # taken verbatim, so the caller keeps complete control.
  #
  # Every component is required, TLS included: defaulting the SSL parameter to ""
  # would let a missing output silently drop the TLS pinning the module exists to
  # enforce. Absent any one of these we compose no URL at all and the precondition
  # in validations.tf reports it. tostring() keeps the emptiness check honest for
  # aurora_db_port, which is a number.
  rdbms_jdbc_required_components = [
    try(local.infra.aurora_jdbc_subprotocol, null),
    try(local.infra.aurora_global_writer_endpoint, null),
    try(local.infra.aurora_db_port, null),
    try(local.infra.aurora_jdbc_wrapper_plugins, null),
    try(local.infra.aurora_jdbc_instance_host_patterns, null),
    try(local.infra.aurora_jdbc_ssl_param, null),
  ]

  rdbms_jdbc_components_available = alltrue([
    for v in local.rdbms_jdbc_required_components : v != null && tostring(v) != ""
  ])

  # The app layer's parameters merge *over* the infra layer's rather than being
  # concatenated after them: two rendered fragments can carry the same key
  # twice, and which occurrence a driver honours is driver-specific. try({})
  # covers an infra state older than the map output — the URL then falls back to
  # the driver's own defaults for these, a tuning loss rather than a correctness
  # one, which is why they are not among the required components above.
  rdbms_jdbc_url_parameters = merge(
    try(local.infra.aurora_jdbc_url_parameters, {}),
    var.rdbms_extra_jdbc_params,
  )

  # Map iteration is key-sorted, so the fragment is stable across plans.
  rdbms_jdbc_url_parameters_rendered = join("", [
    for k, v in local.rdbms_jdbc_url_parameters : "&${k}=${v}"
  ])

  rdbms_jdbc_url_composed = local.rdbms_jdbc_components_available ? join("", [
    "jdbc:aws-wrapper:",
    local.infra.aurora_jdbc_subprotocol,
    "://",
    local.infra.aurora_global_writer_endpoint,
    ":",
    tostring(local.infra.aurora_db_port),
    "/",
    try(local.infra.db_name, "camunda"),
    "?wrapperPlugins=",
    local.infra.aurora_jdbc_wrapper_plugins,
    "&globalClusterInstanceHostPatterns=",
    local.infra.aurora_jdbc_instance_host_patterns,
    local.infra.aurora_jdbc_ssl_param,
    # Query parameters come last, after the module-owned ones above. Both maps
    # are validated the same way — no '&' or '=' in keys or values, and the
    # parameters composed above are reserved — so no entry can append a
    # parameter of its own or shadow one of them.
    local.rdbms_jdbc_url_parameters_rendered,
  ]) : null

  rdbms_jdbc_url = var.rdbms_jdbc_url != null ? var.rdbms_jdbc_url : local.rdbms_jdbc_url_composed

  # Secondary storage environment variables (conditional on storage type)
  rdbms_env_vars = local.infra.secondary_storage_type == "rdbms" ? [
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_AUTOCONFIGURECAMUNDAEXPORTER"
      value = "false"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "rdbms"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_URL"
      value = local.rdbms_jdbc_url
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_USERNAME"
      value = "camunda"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_AUTODDL"
      value = "true"
    },
    {
      name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
      value = "software.amazon.jdbc.Driver"
    },
  ] : []

  opensearch_env_vars_region_0 = local.infra.secondary_storage_type == "opensearch" ? [
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "opensearch"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_URL"
      value = "https://${local.infra.opensearch_region_0_endpoint}"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_USERNAME"
      value = local.infra.db_admin_username
    },
  ] : []

  opensearch_env_vars_region_1 = local.infra.secondary_storage_type == "opensearch" ? [
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "opensearch"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_URL"
      value = "https://${local.infra.opensearch_region_1_endpoint}"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_USERNAME"
      value = local.infra.db_admin_username
    },
  ] : []

  # Common env vars shared by both storage types (admin, connectors, backup)
  common_env_vars = [
    {
      name  = "CAMUNDA_SECURITY_AUTHENTICATION_METHOD"
      value = "basic"
    },
    {
      name  = "CAMUNDA_SECURITY_AUTHENTICATION_UNPROTECTEDAPI"
      value = "false"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_USERNAME"
      value = "admin"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_NAME"
      value = "Admin User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_EMAIL"
      value = "admin@example.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0"
      value = "admin"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_USERNAME"
      value = "connectors"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_NAME"
      value = "Connectors User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_EMAIL"
      value = "connectors@example.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_USERS_0"
      value = "connectors"
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_STORE"
      value = "S3"
    },
  ]
}
