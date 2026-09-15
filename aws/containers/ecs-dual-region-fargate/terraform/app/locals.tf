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
  # The URL splits into the parts before the '?' and the query parameters. Both
  # are required, with no silent defaults: defaulting the database name to
  # "camunda" would point Camunda at a *different* database on a cluster that
  # happens to have one, which connects and behaves plausibly. Absent any part
  # we compose no URL at all and the precondition in validations.tf says which.
  # tostring() keeps the emptiness check honest for aurora_db_port, a number.
  rdbms_jdbc_required_components = [
    try(local.infra.aurora_jdbc_subprotocol, null),
    try(local.infra.aurora_global_writer_endpoint, null),
    try(local.infra.aurora_db_port, null),
    try(local.infra.db_name, null),
  ]

  # The app layer's parameters merge *over* the infra layer's rather than being
  # concatenated after them: two rendered fragments can carry the same key
  # twice, and which occurrence a driver honours is driver-specific.
  rdbms_jdbc_url_parameters = merge(
    try(local.infra.aurora_jdbc_url_parameters, {}),
    var.rdbms_extra_jdbc_params,
  )

  # TLS, the plugin list and the host patterns travel inside that map now, so
  # they are checked by key rather than as separate components. Checking them at
  # all is the point: an infra state predating the map would otherwise compose a
  # URL with no TLS pinning and no failover topology, both silently. Compared
  # lower-cased because the TLS key is spelled sslmode by pgjdbc and sslMode by
  # Connector/J.
  rdbms_jdbc_required_parameters = ["wrapperplugins", "globalclusterinstancehostpatterns", "sslmode"]

  rdbms_jdbc_parameters_present = alltrue([
    for required in local.rdbms_jdbc_required_parameters :
    anytrue([for k in keys(local.rdbms_jdbc_url_parameters) : lower(k) == required])
  ])

  rdbms_jdbc_components_available = alltrue([
    for v in local.rdbms_jdbc_required_components : v != null && tostring(v) != ""
  ]) && local.rdbms_jdbc_parameters_present

  # Map iteration is key-sorted, so the query string is stable across plans.
  # Parameter order carries no meaning to either driver.
  rdbms_jdbc_query_string = join("&", [
    for k, v in local.rdbms_jdbc_url_parameters : "${k}=${v}"
  ])

  rdbms_jdbc_url_composed = local.rdbms_jdbc_components_available ? join("", [
    "jdbc:aws-wrapper:",
    local.infra.aurora_jdbc_subprotocol,
    "://",
    local.infra.aurora_global_writer_endpoint,
    ":",
    tostring(local.infra.aurora_db_port),
    "/",
    local.infra.db_name,
    "?",
    local.rdbms_jdbc_query_string,
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
