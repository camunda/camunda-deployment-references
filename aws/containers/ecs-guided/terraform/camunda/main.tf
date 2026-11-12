# Camunda stage: the Orchestration Cluster and Connectors. It creates no network, storage,
# load balancer or identity provider: all of it arrives through variables, so each of
# those can be brought from anywhere as long as it honours the stage contract.

data "aws_region" "current" {}

locals {
  oidc_enabled = var.oidc != null

  local_zone = one([for z in var.zones : z if z.name == var.zone])

  cluster_size       = sum([for z in var.zones : z.number_of_brokers])
  replication_factor = sum([for z in var.zones : z.number_of_replicas])

  admin_user_password      = var.admin_user_password != "" ? var.admin_user_password : try(random_password.admin_user[0].result, "")
  connectors_user_password = var.connectors_user_password != "" ? var.connectors_user_password : try(random_password.connectors_user[0].result, "")

  service_security_group_ids = [
    var.camunda_ports_security_group_id,
    var.egress_security_group_id,
  ]
}

resource "terraform_data" "validate" {
  lifecycle {
    precondition {
      condition     = local.local_zone != null
      error_message = "zone must be one of the names in zones."
    }
  }
}

# Orders this stage after the storage stage's seed task when both are applied in one go.
resource "terraform_data" "database_ready" {
  input = var.db_seed_done
}

################################################################
#                Basic authentication secrets                  #
################################################################

resource "random_password" "admin_user" {
  count = local.oidc_enabled ? 0 : 1

  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

resource "random_password" "connectors_user" {
  count = local.oidc_enabled ? 0 : 1

  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "admin_user_password" {
  count = local.oidc_enabled ? 0 : 1

  name                    = "${var.prefix}-oc-admin-user-password"
  description             = "Password of the admin user (CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD)"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "admin_user_password" {
  count = local.oidc_enabled ? 0 : 1

  secret_id     = aws_secretsmanager_secret.admin_user_password[0].id
  secret_string = local.admin_user_password
}

resource "aws_secretsmanager_secret" "connectors_user_password" {
  count = local.oidc_enabled ? 0 : 1

  name                    = "${var.prefix}-oc-connectors-client-auth-password"
  description             = "Password of the connectors user (CAMUNDA_CLIENT_AUTH_PASSWORD)"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "connectors_user_password" {
  count = local.oidc_enabled ? 0 : 1

  secret_id     = aws_secretsmanager_secret.connectors_user_password[0].id
  secret_string = local.connectors_user_password
}

resource "aws_iam_policy" "basic_auth_secrets_read" {
  count = local.oidc_enabled ? 0 : 1

  name        = "${var.prefix}-basic-auth-secrets-read"
  description = "Allow the ECS task execution role to read the basic authentication passwords"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.admin_user_password[0].arn,
          aws_secretsmanager_secret.connectors_user_password[0].arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = var.secrets_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basic_auth_secrets_read" {
  count = local.oidc_enabled ? 0 : 1

  role       = var.task_execution_role_name
  policy_arn = aws_iam_policy.basic_auth_secrets_read[0].arn
}

################################################################
#                    Orchestration Cluster                     #
################################################################

module "orchestration_cluster" {
  source = "../../../../modules/ecs/fargate/orchestration-cluster"

  # Start after the database users exist.
  depends_on = [terraform_data.validate, terraform_data.database_ready]

  prefix              = "${var.prefix}-oc"
  ecs_cluster_id      = var.ecs_cluster_id
  vpc_id              = var.vpc_id
  vpc_private_subnets = var.private_subnet_ids
  aws_region          = data.aws_region.current.region

  ecs_task_execution_role_arn = var.task_execution_role_arn
  registry_credentials_arn    = var.registry_credentials_arn

  alb_listener_http_webapp_arn     = var.alb_listener_http_webapp_arn
  alb_listener_http_management_arn = var.alb_listener_http_management_arn
  nlb_arn                          = var.nlb_grpc_arn

  enable_alb_http_webapp_listener_rule = true
  # The management endpoint is unauthenticated.
  enable_alb_http_management_listener_rule = var.enable_management_endpoint
  enable_nlb_grpc_26500_listener           = true

  # Zone-aware brokers from the start: growing into a second region adds a zone.
  zone               = var.zone
  zones              = var.zones
  cluster_size       = local.cluster_size
  replication_factor = local.replication_factor
  partition_count    = var.partition_count
  task_desired_count = try(local.local_zone.number_of_brokers, 0)

  # One lease bucket per zone, created by the object storage stage.
  lease_bucket_name       = var.lease_bucket.bucket_name
  lease_access_policy_arn = var.lease_bucket.access_policy_arn

  environment_variables = concat(
    [
      # Secondary storage: RDBMS (Aurora PostgreSQL, IAM authentication)
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_AUTOCONFIGURECAMUNDAEXPORTER", value = "false" },
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE", value = "rdbms" },
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_URL", value = var.secondary_storage.jdbc_url },
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_USERNAME", value = "camunda" },
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_AUTODDL", value = "true" },
      { name = "SPRING_DATASOURCE_DRIVER_CLASS_NAME", value = var.secondary_storage.jdbc_driver_class_name },
      # Backups
      { name = "CAMUNDA_DATA_BACKUP_STORE", value = "S3" },
      { name = "CAMUNDA_DATA_BACKUP_S3_BUCKETNAME", value = var.backup_bucket_name },
      { name = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME", value = var.backup_bucket_name },
    ],
    var.cross_region_membership ? [
      # The defaults (100 ms probe) are too tight for a link between regions.
      { name = "CAMUNDA_CLUSTER_MEMBERSHIP_PROBETIMEOUT", value = "1000ms" },
      { name = "CAMUNDA_CLUSTER_MEMBERSHIP_FAILURETIMEOUT", value = "10000ms" },
    ] : [],
    var.rdbms_async_replication_monitoring ? [
      # The exporter acknowledges a record only once the replica region has it. See
      # the dual-region reference for the trade-offs of the lag settings.
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_ENABLED", value = "true" },
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_TYPE", value = "LOG_SEQ" },
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_MAXLAG", value = "PT1H" },
      { name = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_ASYNCREPLICATION_PAUSEONMAXLAGEXCEEDED", value = "false" },
    ] : [],
    local.oidc_enabled ? [
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_METHOD", value = "oidc" },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_ISSUERURI", value = var.oidc.issuer_uri },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_CLIENTID", value = var.oidc.orchestration.client_id },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_REDIRECTURI", value = var.oidc.redirect_uri },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_USERNAMECLAIM", value = var.oidc.username_claim },
      # Detects machine-to-machine callers by the client id claim; without it a service
      # account token is treated as a user and never matches the client mappings below.
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_CLIENTIDCLAIM", value = var.oidc.client_id_claim },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_AUDIENCE", value = var.oidc.audience },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0", value = var.oidc.admin_claim },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_CLIENTS_0", value = var.oidc.orchestration.client_id },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_CLIENTS_0", value = var.oidc.connectors.client_id },
      ] : [
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_USERNAME", value = "admin" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_NAME", value = "Admin User" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_EMAIL", value = "admin@example.com" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0", value = "admin" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_USERNAME", value = "connectors" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_NAME", value = "Connectors User" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_EMAIL", value = "connectors@example.com" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_USERS_0", value = "connectors" },
    ],
  )

  secrets = local.oidc_enabled ? [
    { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_CLIENTSECRET", valueFrom = var.oidc.orchestration.client_secret_arn },
    ] : [
    { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD", valueFrom = aws_secretsmanager_secret.admin_user_password[0].arn },
    { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_PASSWORD", valueFrom = aws_secretsmanager_secret.connectors_user_password[0].arn },
  ]

  service_security_group_ids = concat(local.service_security_group_ids, [var.efs_security_group_id])
  efs_security_group_ids     = [var.efs_security_group_id]

  extra_task_role_attachments = [
    var.rds_db_connect_policy_arn,
    var.backup_access_policy_arn,
  ]

  initial_contact_points            = var.initial_contact_points
  internal_nlb_arn                  = var.raft_nlb_arn
  enable_internal_nlb_raft_listener = var.enable_raft_listener
}

################################################################
#                          Connectors                          #
################################################################

module "connectors" {
  source = "../../../../modules/ecs/fargate/connectors"

  prefix                               = "${var.prefix}-oc"
  ecs_cluster_id                       = var.ecs_cluster_id
  vpc_id                               = var.vpc_id
  vpc_private_subnets                  = var.private_subnet_ids
  aws_region                           = data.aws_region.current.region
  s2s_cloudmap_namespace               = module.orchestration_cluster.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = var.alb_listener_http_webapp_arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster.log_group_name

  ecs_task_execution_role_arn = var.task_execution_role_arn
  registry_credentials_arn    = var.registry_credentials_arn

  service_security_group_ids = local.service_security_group_ids

  environment_variables = concat(
    [
      # Connection to the Orchestration Cluster over Service Connect
      { name = "CAMUNDA_CLIENT_MODE", value = "self-managed" },
      { name = "CAMUNDA_CLIENT_RESTADDRESS", value = "http://${module.orchestration_cluster.rest_service_connect}:8080" },
      { name = "CAMUNDA_CLIENT_GRPCADDRESS", value = "http://${module.orchestration_cluster.grpc_service_connect}:26500" },
    ],
    local.oidc_enabled ? [
      { name = "CAMUNDA_CLIENT_AUTH_CLIENTID", value = var.oidc.connectors.client_id },
      { name = "CAMUNDA_CLIENT_AUTH_TOKENURL", value = var.oidc.token_uri },
      { name = "CAMUNDA_CLIENT_AUTH_AUDIENCE", value = var.oidc.audience },
      ] : [
      { name = "CAMUNDA_CLIENT_AUTH_METHOD", value = "basic" },
      { name = "CAMUNDA_CLIENT_AUTH_USERNAME", value = "connectors" },
    ],
    local.oidc_enabled && var.oidc.connectors.token_scope != "" ? [
      { name = "CAMUNDA_CLIENT_AUTH_SCOPE", value = var.oidc.connectors.token_scope },
    ] : [],
  )

  secrets = local.oidc_enabled ? [
    { name = "CAMUNDA_CLIENT_AUTH_CLIENTSECRET", valueFrom = var.oidc.connectors.client_secret_arn },
    ] : [
    { name = "CAMUNDA_CLIENT_AUTH_PASSWORD", valueFrom = aws_secretsmanager_secret.connectors_user_password[0].arn },
  ]

  task_desired_count = 1
}
