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
    # Async replication monitoring. The exporter acknowledges a record to the
    # broker only once Aurora reports it replicated, which holds back Zeebe log
    # compaction so an unplanned writer promotion can be replayed from the log.
    # reference: https://docs.camunda.io/docs/self-managed/concepts/databases/relational-db/database-configuration/#multi-region-support
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_ENABLED"
      value = "true"
    },
    # LOG_SEQ reads Aurora's own replication position and is the engine default,
    # pinned here because it is not universally supported: Aurora Global
    # Database for PostgreSQL and MySQL, MSSQL and PostgreSQL only. Nothing
    # downgrades silently. ReplicationLsnProviderFactory.create() throws at
    # startup on anything else, naming the reason, so pointing rdbms_jdbc_url at
    # plain MySQL or a non-global Aurora fails the deployment instead of
    # quietly dropping the replication signal. Moving off Aurora means choosing
    # DELAY here and giving it its own delay value.
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_TYPE"
      value = "LOG_SEQ"
    },
    # The age the oldest unconfirmed exporter position may reach before the
    # exporter pauses. Under LOG_SEQ this is not an Aurora-reported lag figure,
    # and it is not an acknowledgement delay either: confirmed positions are
    # acknowledged as soon as Aurora reports them. It is the longest
    # replication interruption to ride out. A cross-region writer promotion
    # under load runs past the engine default of PT15M, which would pause the
    # exporter during the very event this architecture treats as routine, so
    # the budget is an hour.
    #
    # It is not a storage control: the exporter position cannot advance while
    # Aurora is behind, so log segments accumulate on the EFS data volume for
    # the length of the outage whatever this value is. Raising it does not
    # blind you to a lost secondary either, though the timing depends on what
    # is in flight: computePauseLag() reports worst-case lag only while the
    # queue is empty, which pauses at the next poll past any budget. With
    # positions already queued the queue-head age governs, so that case waits
    # out max-lag like any other.
    #
    # min-sync-replicas stays at its default of 1: the global cluster has
    # exactly one secondary to wait for.
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_MAXLAG"
      value = "PT1H"
    },
    # Not an RPO control, and not a disk control either. Acknowledgement is
    # gated on confirmed replication either way, so no data is lost either way,
    # and the Zeebe log grows either way: the exporter position cannot advance
    # past records the standby has not confirmed, so compaction stays blocked
    # for as long as Aurora is behind, paused or not.
    #
    # What it decides is whether the exporter keeps pushing writes at a database
    # that is already lagging, or stops and says so. Paused, export() raises an
    # ExporterException, which surfaces in the exporter metrics and the broker
    # log instead of degrading quietly, and it stops adding load to the thing
    # that needs to catch up. Zeebe keeps processing throughout, and the APIs
    # serve stale data until Aurora recovers.
    #
    # EFS is elastic, so a prolonged outage does not hit a capacity wall the
    # way a fixed volume would: it grows storage and burns throughput for as
    # long as it lasts. Monitor EFS storage growth and throughput and alert on
    # replication lag regardless of this setting. It buys observability and
    # back-pressure, not headroom.
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_PAUSEONMAXLAGEXCEEDED"
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
