data "aws_region" "current" {}

module "orchestration_cluster" {
  source = "../../../../modules/ecs/fargate/orchestration-cluster"

  depends_on = [null_resource.run_db_seed_task]

  prefix              = "${var.prefix}-oc1"
  ecs_cluster_id      = aws_ecs_cluster.ecs.id
  vpc_id              = module.vpc.vpc_id
  vpc_private_subnets = module.vpc.private_subnets
  aws_region          = data.aws_region.current.region

  # IAM Roles (execution role centrally managed, task role module-specific)
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  # Load Balancer configuration
  alb_listener_http_webapp_arn     = aws_lb_listener.http_webapp.arn
  alb_listener_http_management_arn = aws_lb_listener.http_management.arn
  nlb_arn                          = aws_lb.grpc.arn

  enable_alb_http_webapp_listener_rule = true
  # management endpoint is unprotected, only enable if you know what you are doing.
  # Consider secure access alternatives via temporary jump host / VPN connected to VPC / lambda or step functions.
  enable_alb_http_management_listener_rule = false
  enable_nlb_grpc_26500_listener           = true

  environment_variables = concat([
    {
      name  = "CAMUNDA_CLUSTER_REPLICATIONFACTOR"
      value = "3"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONCOUNT"
      value = "3"
    },
    # Secondary Storage - RDBMS (Aurora PostgreSQL with IAM Auth)
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
      value = "jdbc:aws-wrapper:postgresql://${module.postgresql.aurora_endpoint}:5432/${var.db_name}?wrapperPlugins=iam"
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
    # Backup / Restore configuration
    {
      name  = "CAMUNDA_DATA_BACKUP_STORE"
      value = "S3"
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_S3_BUCKETNAME"
      value = aws_s3_bucket.backup.bucket
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
      value = aws_s3_bucket.backup.bucket
    },
    ],
    # --- Authentication: basic (built-in users) or OIDC (Keycloak realm) ---
    local.oidc_enabled ? [
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_METHOD", value = "oidc" },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_ISSUERURI", value = local.camunda_realm_issuer_public },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_CLIENTID", value = "orchestration" },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_REDIRECTURI", value = "${local.alb_base_url}/sso-callback" },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_USERNAMECLAIM", value = "preferred_username" },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_AUDIENCE", value = "orchestration-api" },
      # The realm 'admin' user (created by Identity) becomes platform admin.
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0", value = "admin" },
      # Connectors authenticates as an OIDC client (m2m), mapped to the connectors role.
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_CLIENTS_0", value = "connectors" },
      ] : [
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_USERNAME", value = "admin" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_NAME", value = "Admin User" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_EMAIL", value = "admin@example.com" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0", value = "admin" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_USERNAME", value = "connectors" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_NAME", value = "Connectors User" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_EMAIL", value = "connectors@example.com" },
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_USERS_0", value = "connectors" },
  ])

  # Prefer ECS task secrets for sensitive values (container definition 'secrets')
  secrets = local.oidc_enabled ? [
    {
      name      = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_CLIENTSECRET"
      valueFrom = aws_secretsmanager_secret.orchestration_oidc_client_secret[0].arn
    }
    ] : [
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD"
      valueFrom = aws_secretsmanager_secret.orchestration_admin_user_password.arn
    },
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_PASSWORD"
      valueFrom = aws_secretsmanager_secret.connectors_client_auth_password.arn
    }
  ]

  registry_credentials_arn = join("", aws_secretsmanager_secret.registry_credentials[*].arn)

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
    aws_security_group.efs.id,
  ]
  efs_security_group_ids = [aws_security_group.efs.id]

  task_desired_count = 3

  # Pass additional policies to orchestration cluster task role
  extra_task_role_attachments = [
    aws_iam_policy.rds_db_connect_camunda.arn,
    aws_iam_policy.s3_backup_access_policy.arn,
  ]

  # Restore configuration (uncomment to enable restore from backup)
  # restore_enabled   = true
  # restore_backup_id = "my-backup-id"

}

module "connectors" {
  source = "../../../../modules/ecs/fargate/connectors"

  prefix                               = "${var.prefix}-oc1"
  ecs_cluster_id                       = aws_ecs_cluster.ecs.id
  vpc_id                               = module.vpc.vpc_id
  vpc_private_subnets                  = module.vpc.private_subnets
  aws_region                           = data.aws_region.current.region
  s2s_cloudmap_namespace               = module.orchestration_cluster.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = aws_lb_listener.http_webapp.arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster.log_group_name

  # IAM Roles (execution role centrally managed, task role module-specific)
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  registry_credentials_arn = join("", aws_secretsmanager_secret.registry_credentials[*].arn)

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]

  environment_variables = concat([
    # Self-managed connection to the orchestration cluster (internal Service Connect)
    {
      name  = "CAMUNDA_CLIENT_MODE",
      value = "self-managed"
    },
    {
      name  = "CAMUNDA_CLIENT_RESTADDRESS",
      value = "http://${module.orchestration_cluster.rest_service_connect}:8080"
    },
    {
      name  = "CAMUNDA_CLIENT_GRPCADDRESS",
      value = "http://${module.orchestration_cluster.grpc_service_connect}:26500"
    },
    ],
    # Auth to the orchestration cluster: basic user or OIDC client-credentials.
    # Connectors fetches tokens via the shared ALB (same host as every other actor)
    # so the token `iss` is the ALB URL and matches what orchestration validates.
    local.oidc_enabled ? [
      { name = "CAMUNDA_CLIENT_AUTH_CLIENTID", value = "connectors" },
      { name = "CAMUNDA_CLIENT_AUTH_TOKENURL", value = "${local.camunda_realm_issuer_public}/protocol/openid-connect/token" },
      { name = "CAMUNDA_CLIENT_AUTH_AUDIENCE", value = "orchestration-api" },
      ] : [
      { name = "CAMUNDA_CLIENT_AUTH_METHOD", value = "basic" },
      { name = "CAMUNDA_CLIENT_AUTH_USERNAME", value = "connectors" },
  ])

  # Prefer ECS task secrets for sensitive values (container definition 'secrets')
  secrets = local.oidc_enabled ? [
    {
      name      = "CAMUNDA_CLIENT_AUTH_CLIENTSECRET"
      valueFrom = aws_secretsmanager_secret.connectors_oidc_client_secret[0].arn
    }
    ] : [
    {
      name      = "CAMUNDA_CLIENT_AUTH_PASSWORD"
      valueFrom = aws_secretsmanager_secret.connectors_client_auth_password.arn
    }
  ]

  task_desired_count = 1

  # Pass additional policies to connectors task role
  extra_task_role_attachments = []

}

module "management_identity" {
  source = "../../../../modules/ecs/fargate/management-identity"

  depends_on = [null_resource.run_db_seed_task, module.keycloak]

  prefix                      = "${var.prefix}-oc1"
  ecs_cluster_id              = aws_ecs_cluster.ecs.id
  vpc_id                      = module.vpc.vpc_id
  vpc_private_subnets         = module.vpc.private_subnets
  aws_region                  = data.aws_region.current.region
  s2s_cloudmap_namespace      = module.orchestration_cluster.s2s_cloudmap_namespace
  log_group_name              = module.orchestration_cluster.log_group_name
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
  registry_credentials_arn    = join("", aws_secretsmanager_secret.registry_credentials[*].arn)

  # ALB exposure is opt-in. Flip to true (and confirm the context path) once
  # Identity should be reachable through the shared ALB.
  alb_listener_http_webapp_arn         = aws_lb_listener.http_webapp.arn
  enable_alb_http_webapp_listener_rule = false

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]

  environment_variables = [
    # --- Database (password auth to a dedicated Aurora database) ---
    {
      name  = "IDENTITY_DATABASE_HOST"
      value = module.postgresql.aurora_endpoint
    },
    {
      name  = "IDENTITY_DATABASE_PORT"
      value = "5432"
    },
    {
      name  = "IDENTITY_DATABASE_NAME"
      value = var.identity_db_name
    },
    {
      name  = "IDENTITY_DATABASE_USERNAME"
      value = var.identity_db_username
    },
    # --- Server / management ports ---
    {
      name  = "SERVER_PORT"
      value = "8084"
    },
    {
      name  = "MANAGEMENT_SERVER_PORT"
      value = "8082"
    },
    # --- Actuator probes (so /actuator/health/liveness is exposed) ---
    {
      name  = "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE"
      value = "health"
    },
    {
      name  = "MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED"
      value = "true"
    },
    # --- Identity provider (Keycloak) ---
    {
      name  = "SPRING_PROFILES_ACTIVE"
      value = "keycloak"
    },
    {
      name  = "KEYCLOAK_SETUP_USER"
      value = var.keycloak_admin_username
    },
    {
      name  = "SPRING_APPLICATION_JSON"
      value = local.identity_realm_json
    },
  ]

  secrets = concat(
    [
      { name = "IDENTITY_DATABASE_PASSWORD", valueFrom = aws_secretsmanager_secret.identity_db_password.arn },
      { name = "CAMUNDA_IDENTITY_CLIENT_SECRET", valueFrom = aws_secretsmanager_secret.identity_client_secret.arn },
      { name = "KEYCLOAK_SETUP_PASSWORD", valueFrom = aws_secretsmanager_secret.keycloak_admin_password.arn },
      { name = "KEYCLOAK_REALM_ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.realm_admin_user_password.arn },
    ],
    var.enable_orchestration_oidc_client ? [{ name = "VALUES_KEYCLOAK_INIT_ORCHESTRATION_SECRET", valueFrom = aws_secretsmanager_secret.orchestration_oidc_client_secret[0].arn }] : [],
    var.enable_connectors_oidc_client ? [{ name = "VALUES_KEYCLOAK_INIT_CONNECTORS_SECRET", valueFrom = aws_secretsmanager_secret.connectors_oidc_client_secret[0].arn }] : [],
    var.enable_optimize_oidc_client ? [{ name = "VALUES_KEYCLOAK_INIT_OPTIMIZE_SECRET", valueFrom = aws_secretsmanager_secret.optimize_oidc_client_secret[0].arn }] : [],
    var.enable_console_oidc_client ? [{ name = "VALUES_KEYCLOAK_INIT_CONSOLE_SECRET", valueFrom = aws_secretsmanager_secret.console_oidc_client_secret[0].arn }] : [],
  )

  task_desired_count          = 1
  extra_task_role_attachments = []

  wait_for_steady_state = true
}

module "keycloak" {
  source = "../../../../modules/ecs/fargate/keycloak"

  depends_on = [null_resource.run_db_seed_task]

  prefix                      = "${var.prefix}-oc1"
  ecs_cluster_id              = aws_ecs_cluster.ecs.id
  vpc_id                      = module.vpc.vpc_id
  vpc_private_subnets         = module.vpc.private_subnets
  aws_region                  = data.aws_region.current.region
  s2s_cloudmap_namespace      = module.orchestration_cluster.s2s_cloudmap_namespace
  log_group_name              = module.orchestration_cluster.log_group_name
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
  registry_credentials_arn    = join("", aws_secretsmanager_secret.registry_credentials[*].arn)

  # Internal Service Connect (keycloak:18080) is enough for Identity in basic mode.
  # In oidc mode the browser must reach Keycloak to complete the login redirect,
  # so the shared ALB (/auth*) is enabled.
  alb_listener_http_webapp_arn         = aws_lb_listener.http_webapp.arn
  enable_alb_http_webapp_listener_rule = local.oidc_enabled

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]

  environment_variables = [
    { name = "KC_DB", value = "postgres" },
    { name = "KC_DB_URL", value = "jdbc:postgresql://${module.postgresql.aurora_endpoint}:5432/${var.keycloak_db_name}" },
    { name = "KC_DB_USERNAME", value = var.keycloak_db_username },
    { name = "KC_BOOTSTRAP_ADMIN_USERNAME", value = var.keycloak_admin_username },
    { name = "KC_HTTP_ENABLED", value = "true" },
    { name = "KC_HTTP_PORT", value = "18080" },
    { name = "KC_HTTP_RELATIVE_PATH", value = "/auth" },
    { name = "KC_HEALTH_ENABLED", value = "true" },
    # hostname-strict=false lets Keycloak derive its frontend URL (and token `iss`)
    # from the request host. In oidc mode every actor (browser, orchestration
    # discovery, connectors) reaches Keycloak via the shared ALB, so `iss` is
    # consistently the ALB URL without pinning KC_HOSTNAME. Production behind TLS
    # would instead pin KC_HOSTNAME + KC_PROXY_HEADERS=xforwarded.
    { name = "KC_HOSTNAME_STRICT", value = "false" },
    { name = "KC_TRANSACTION_XA_ENABLED", value = "false" },
    # Single-instance deployment (task_desired_count = 1): use the local cache so
    # Keycloak does not form a JGroups/Infinispan cluster. Otherwise a rolling
    # redeploy briefly runs two tasks that cannot reach each other on the JGroups
    # ports (7800/57800, not opened in the intra-VPC SG); the new node's cluster
    # health check stays DOWN and the ECS circuit breaker fails the deployment.
    { name = "KC_CACHE", value = "local" },
  ]

  secrets = [
    { name = "KC_DB_PASSWORD", valueFrom = aws_secretsmanager_secret.keycloak_db_password.arn },
    { name = "KC_BOOTSTRAP_ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.keycloak_admin_password.arn },
  ]

  task_desired_count          = 1
  wait_for_steady_state       = true
  extra_task_role_attachments = []
}
