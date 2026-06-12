################################
# Computed Values             #
################################

resource "random_id" "bucket_suffix" {
  byte_length = 3 # 6 hex characters
}

locals {
  prefix        = var.cluster_name
  bucket_suffix = random_id.bucket_suffix.hex

  # Region configuration (derived from variables)
  owner = {
    region         = var.region_0
    vpc_cidr_block = var.region_0_cidr
  }
  accepter = {
    region         = var.region_1
    vpc_cidr_block = var.region_1_cidr
  }

  # Truncate prefix for AWS resources with name length limits (e.g., ALB target groups: 32 chars)
  prefix_truncated = substr(local.prefix, 0, 14)

  # Region-specific prefixes
  prefix_region_0 = "${local.prefix}-r0"
  prefix_region_1 = "${local.prefix}-r1"

  # Zeebe dual-region cluster configuration
  cluster_size        = 8
  replication_factor  = 4
  partition_count     = 8
  brokers_per_region  = 4
  replicas_per_region = local.replication_factor / 2

  # Region-aware partitioning environment variables (shared by both regions)
  # Region-aware partitioning env vars
  # Note: CAMUNDA_CLUSTER_SIZE, REPLICATIONFACTOR, PARTITIONCOUNT, and INITIALCONTACTPOINTS
  # are already set by the orchestration-cluster module via its variables.
  partitioning_env_vars = [
    {
      name  = "CAMUNDA_CLUSTER_NAME"
      value = var.cluster_name
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_SCHEME"
      value = "REGION_AWARE"
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
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NAME"
      value = var.region_0
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NUMBEROFREPLICAS"
      value = tostring(local.replicas_per_region)
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NUMBEROFBROKERS"
      value = tostring(local.brokers_per_region)
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_PRIORITY"
      value = "1000"
    },
    # Region 1 topology
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NAME"
      value = var.region_1
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NUMBEROFREPLICAS"
      value = tostring(local.replicas_per_region)
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NUMBEROFBROKERS"
      value = tostring(local.brokers_per_region)
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_PRIORITY"
      value = "500"
    },
  ]

  # Region-specific: tells each broker which region it belongs to
  cluster_region_env_region_0 = [
    {
      name  = "CAMUNDA_CLUSTER_REGION"
      value = var.region_0
    },
  ]

  cluster_region_env_region_1 = [
    {
      name  = "CAMUNDA_CLUSTER_REGION"
      value = var.region_1
    },
  ]

  # Aurora Global instance host patterns for AWS JDBC Wrapper
  # Derived from cluster endpoints: strip cluster identifier prefix to get the DNS suffix,
  # then prepend "?." so the wrapper can resolve individual instance endpoints.
  # e.g. "ecs-dr-test-r0-camunda-db.cluster-abc123.eu-west-2.rds.amazonaws.com"
  #   → instance pattern: "?.abc123.eu-west-2.rds.amazonaws.com"
  aurora_primary_instance_pattern = var.secondary_storage_type == "rdbms" ? "?.${
    replace(module.aurora_global[0].primary_cluster_endpoint, "${module.aurora_global[0].primary_cluster_identifier}.cluster-", "")
  }" : ""
  aurora_secondary_instance_pattern = var.secondary_storage_type == "rdbms" ? "?.${
    replace(module.aurora_global[0].secondary_cluster_endpoint, "${module.aurora_global[0].secondary_cluster_identifier}.cluster-", "")
  }" : ""

  # Secondary storage environment variables (conditional on storage type)
  rdbms_env_vars = var.secondary_storage_type == "rdbms" ? [
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
      value = "jdbc:aws-wrapper:postgresql://${module.aurora_global[0].primary_cluster_endpoint}:5432/${var.db_name}?wrapperPlugins=iam,failover&globalClusterInstanceHostPatterns=${local.aurora_primary_instance_pattern},${local.aurora_secondary_instance_pattern}"
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

  opensearch_env_vars_region_0 = var.secondary_storage_type == "opensearch" ? [
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "opensearch"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_URL"
      value = "https://${module.opensearch_region_0[0].opensearch_domain_endpoint}"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_USERNAME"
      value = var.db_admin_username
    },
  ] : []

  opensearch_env_vars_region_1 = var.secondary_storage_type == "opensearch" ? [
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "opensearch"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_URL"
      value = "https://${module.opensearch_region_1[0].opensearch_domain_endpoint}"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_OPENSEARCH_USERNAME"
      value = var.db_admin_username
    },
  ] : []

  # Common env vars shared by both storage types (admin, connectors, backup)
  common_env_vars = [
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
