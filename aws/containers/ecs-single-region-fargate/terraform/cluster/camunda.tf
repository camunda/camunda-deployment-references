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
  alb_listener_http_webapp_arn     = local.webapp_listener_arn
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
    # --- Authentication: basic (built-in users) or OIDC (bundled Keycloak / external) ---
    local.oidc_enabled ? [
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_METHOD", value = "oidc" },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_ISSUERURI", value = local.oidc.issuer_uri },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_CLIENTID", value = local.oidc.orchestration.client_id },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_REDIRECTURI", value = local.oidc.redirect_uri },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_USERNAMECLAIM", value = "preferred_username" },
      # Detect m2m (client-credentials) callers by the client_id claim; without this,
      # a service-account token is treated as a user (preferred_username =
      # service-account-<client>) and never matches the admin/connectors client
      # mappings below, so deployments are rejected 403. The realm emits client_id.
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_CLIENTIDCLAIM", value = "client_id" },
      { name = "CAMUNDA_SECURITY_AUTHENTICATION_OIDC_AUDIENCE", value = local.oidc.audience },
      # Admin user identifier from the username claim (the bundled realm's 'admin';
      # for external OIDC set this to your admin's preferred_username).
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0", value = "admin" },
      # The orchestration client is also an admin m2m client (matches Camunda's
      # reference admin.clients), so automation/CI can deploy and operate over
      # client-credentials; the least-privilege connectors client cannot.
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_CLIENTS_0", value = local.oidc.orchestration.client_id },
      # Connectors authenticates as an OIDC client (m2m), mapped to the connectors role.
      { name = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_CLIENTS_0", value = local.oidc.connectors.client_id },
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
      valueFrom = local.oidc.orchestration.client_secret_arn
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
  alb_listener_http_webapp_arn         = local.webapp_listener_arn
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
      { name = "CAMUNDA_CLIENT_AUTH_CLIENTID", value = local.oidc.connectors.client_id },
      { name = "CAMUNDA_CLIENT_AUTH_TOKENURL", value = local.oidc.token_uri },
      { name = "CAMUNDA_CLIENT_AUTH_AUDIENCE", value = local.oidc.audience },
      ] : [
      { name = "CAMUNDA_CLIENT_AUTH_METHOD", value = "basic" },
      { name = "CAMUNDA_CLIENT_AUTH_USERNAME", value = "connectors" },
  ])

  # Prefer ECS task secrets for sensitive values (container definition 'secrets')
  secrets = local.oidc_enabled ? [
    {
      name      = "CAMUNDA_CLIENT_AUTH_CLIENTSECRET"
      valueFrom = local.oidc.connectors.client_secret_arn
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

  # Management Identity is deployed only when OIDC is enabled (basic mode uses
  # built-in users and needs no IdP). It always runs the generic OIDC profile
  # against local.oidc — identical whether the IdP is the bundled Keycloak or an
  # external provider; the component never references Keycloak.
  count = local.oidc_enabled ? 1 : 0

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

  # ALB exposure is opt-in. Flip to true (and confirm the context path) once
  # Identity should be reachable through the shared ALB.
  alb_listener_http_webapp_arn         = local.webapp_listener_arn
  enable_alb_http_webapp_listener_rule = false

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]

  environment_variables = concat([
    # --- Database (dedicated Aurora database, IAM auth via the AWS JDBC wrapper) ---
    #
    # The image ships the AWS Advanced JDBC wrapper (BOOT-INF/lib/aws-advanced-jdbc-
    # wrapper-*.jar), and the datasource is built by Spring Boot from the standard
    # spring.datasource.* properties, so pointing them at the wrapper switches the
    # component to short-lived IAM tokens — the same mechanism the orchestration cluster
    # and Camunda Hub use. Environment variables outrank the image's bundled
    # application.yaml, whose defaults (IDENTITY_DATABASE_* + org.postgresql.Driver) are
    # plain password auth; those defaults are what make it look like the wrapper is
    # unavailable. No static database password is handed to the task.
    {
      name  = "SPRING_DATASOURCE_URL"
      value = "jdbc:aws-wrapper:postgresql://${module.postgresql.aurora_endpoint}:5432/${var.identity_db_name}?wrapperPlugins=iam"
    },
    {
      name  = "SPRING_DATASOURCE_USERNAME"
      value = var.identity_db_username
    },
    {
      name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
      value = "software.amazon.jdbc.Driver"
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
    # --- Identity provider: generic OIDC (bundled Keycloak or external), no realm
    #     bootstrap. The IdP owns clients/users; Identity is a resource server here.
    #     In generic OIDC mode Identity handles login and token validation only:
    #     user-profile management, RP-initiated logout and role/group sync *from the
    #     IdP* are not available. Authorization is therefore split — the Orchestration
    #     Cluster is seeded Camunda-side (CAMUNDA_SECURITY_INITIALIZATION_* above),
    #     while the components that resolve permissions through Identity (Web Modeler /
    #     Camunda Hub) need Identity's own roles declared and granted by claim; see
    #     identity_authorization.tf and var.enable_web_modeler_authorization.
    { name = "SPRING_PROFILES_ACTIVE", value = "oidc" },
    { name = "CAMUNDA_IDENTITY_TYPE", value = "GENERIC" },
    { name = "CAMUNDA_IDENTITY_BASE_URL", value = local.identity_public_base },
    { name = "CAMUNDA_IDENTITY_ISSUER", value = local.oidc.issuer_uri },
    # Backend metadata/JWKS fetches use the in-VPC address; see local.oidc_issuer_backend_uri.
    { name = "CAMUNDA_IDENTITY_ISSUER_BACKEND_URL", value = local.oidc_issuer_backend_uri },
    { name = "CAMUNDA_IDENTITY_CLIENT_ID", value = local.oidc.identity.client_id },
    { name = "CAMUNDA_IDENTITY_AUDIENCE", value = local.oidc.identity.audience },
    ],
    # First admin is granted by matching this claim/value (write-once at first boot).
    #
    # Mutually exclusive with the declared mapping rule below. Identity bootstraps a
    # mapping rule named "Default" from these two vars, and the initializer that reads
    # `identity.mapping-rules` de-duplicates on the (claim-name, claim-value, rule-type)
    # triple rather than on the rule name — so a declared rule matching the same claim is
    # silently skipped and the roles it grants are never applied. When the authorization
    # model is seeded we therefore let the declared rule do the bootstrapping too: it
    # grants ManagementIdentity plus the Web Modeler roles, a superset of the
    # auto-created one. See identity_authorization.tf.
    local.webmodeler_authorization_enabled ? [] : [
      { name = "IDENTITY_INITIAL_CLAIM_NAME", value = local.identity_admin_claim_name },
      { name = "IDENTITY_INITIAL_CLAIM_VALUE", value = local.identity_admin_claim_value },
    ],
    # Identity's own authorization model (roles + claim-based grants). Opt-in, because
    # it only matters once a component that resolves permissions through Identity is
    # deployed; see identity_authorization.tf.
    local.webmodeler_authorization_enabled ? [
      { name = "SPRING_APPLICATION_JSON", value = local.identity_authorization_json },
    ] : [],
  )

  # No IDENTITY_DATABASE_PASSWORD: the task authenticates to Aurora with an IAM token.
  # The password still exists in Secrets Manager because the DB seed uses it to bootstrap
  # the role (see postgres_seed.tf).
  secrets = [
    { name = "CAMUNDA_IDENTITY_CLIENT_SECRET", valueFrom = local.oidc.identity.client_secret_arn },
  ]

  task_desired_count          = 1
  extra_task_role_attachments = [aws_iam_policy.rds_db_connect_identity[0].arn]

  wait_for_steady_state = true
}

################################################################
#              Camunda Hub (Web Modeler) - optional            #
################################################################
# Camunda Hub bundles Web Modeler (+ Console). It authenticates via OIDC against
# the same provider-agnostic local.oidc interface as every other component, so it
# is only valid when authentication_mode = "oidc" (guarded in auth_mode.tf).
# Enabling it also registers the web-modeler client in the bundled Keycloak realm
# (keycloak_realm.tf).

locals {
  # Single source of truth for the Hub URL context path: passed to the module and
  # reused for the OIDC redirect (keycloak_realm.tf), server URL and websocket path.
  camunda_hub_context_path = "/hub"

  # Cluster generation reported to Camunda Hub. Values >= 8.8 select the REST/gRPC
  # cluster API (and drop the legacy url.zeebe requirement); a blank value makes the
  # app fail to start on `camunda.modeler.clusters[0].version`.
  # TODO: [release-duty] keep in sync with the orchestration cluster image tag.
  camunda_hub_cluster_version = "8.10.0"

  # Orchestration cluster registration for Camunda Hub, in the `components[]` schema
  # introduced by 8.10 (camundaPlatform.defaultWebModelerCluster in the reference chart).
  #
  # The pre-8.10 flat form (clusters[0].url.{rest,grpc}) still boots, but it carries no
  # readiness URL, so Console cannot resolve cluster health and renders the cluster as
  # "Unhealthy" with status UNKNOWN even while it is fully operational. Health is probed
  # on the *management* port: the API port serves no actuator (8080/actuator/health is a
  # 404) and the v2 API needs a bearer token that a background probe does not hold.
  #
  # Nested lists cannot be expressed as relaxed-binding environment variables, so the
  # whole block is handed to the task as a single SPRING_APPLICATION_JSON value (same
  # approach as identity_authorization.tf). Defined here in full rather than alongside
  # flat CAMUNDA_MODELER_CLUSTERS_0_* vars: SPRING_APPLICATION_JSON outranks OS env vars
  # in Spring's property order, and list properties are not merged across sources.
  camunda_hub_clusters_json = jsonencode({
    camunda = {
      modeler = {
        clusters = [
          {
            id             = "default-cluster"
            name           = "default-cluster"
            version        = local.camunda_hub_cluster_version
            authentication = "BEARER_TOKEN"
            authorizations = { enabled = local.oidc_enabled }
            components = [
              {
                name    = "Orchestration Cluster"
                type    = "orchestration"
                version = local.camunda_hub_cluster_version
                urls = {
                  grpc      = "grpc://${module.orchestration_cluster.grpc_service_connect}:26500"
                  rest      = "http://${module.orchestration_cluster.rest_service_connect}:8080"
                  readiness = "http://${module.orchestration_cluster.management_service_connect}:9600/actuator/health/readiness"
                }
              },
            ]
          },
        ]
      }
    }
  })
}

module "camunda_hub" {
  count  = var.enable_camunda_hub ? 1 : 0
  source = "../../../../modules/ecs/fargate/camunda-hub"

  depends_on = [null_resource.run_camunda_hub_db_seed, module.management_identity]

  prefix                               = "${var.prefix}-oc1"
  ecs_cluster_id                       = aws_ecs_cluster.ecs.id
  vpc_id                               = module.vpc.vpc_id
  vpc_private_subnets                  = module.vpc.private_subnets
  aws_region                           = data.aws_region.current.region
  s2s_cloudmap_namespace               = module.orchestration_cluster.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = local.webapp_listener_arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster.log_group_name

  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  restapi_image    = var.camunda_hub_restapi_image
  websockets_image = var.camunda_hub_websockets_image
  context_path     = local.camunda_hub_context_path

  # Only attach registry credentials for the private Camunda registry; public
  # Docker Hub images (the trial-capable defaults) pull without credentials, and
  # passing docker.io creds confuses ECS. Mirrors the ecs-dual-region pattern.
  registry_credentials_arn = (
    startswith(var.camunda_hub_restapi_image, "registry.camunda.cloud/") ||
    startswith(var.camunda_hub_websockets_image, "registry.camunda.cloud/")
  ) ? join("", aws_secretsmanager_secret.registry_credentials[*].arn) : ""

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]

  # Shared Pusher secret + optional license (root-owned in Secrets Manager).
  pusher_app_key_secret_arn    = aws_secretsmanager_secret.pusher_app_key[0].arn
  pusher_app_secret_secret_arn = aws_secretsmanager_secret.pusher_app_secret[0].arn
  license_secret_arn           = join("", aws_secretsmanager_secret.camunda_license_key[*].arn)

  environment_variables = [
    # --- Database (dedicated camunda-hub database, IAM auth via AWS JDBC wrapper) ---
    { name = "SPRING_DATASOURCE_URL", value = "jdbc:aws-wrapper:postgresql://${module.postgresql.aurora_endpoint}:5432/camunda-hub?wrapperPlugins=iam" },
    { name = "SPRING_DATASOURCE_USERNAME", value = "camunda-hub" },
    { name = "SPRING_DATASOURCE_DRIVER_CLASS_NAME", value = "software.amazon.jdbc.Driver" },

    # --- Console feature (Camunda Hub consolidation) ---
    { name = "CAMUNDA_MODELER_FEATURE_CONSOLE_ENABLED", value = "true" },

    # --- Mail (from-address is required by the app; SMTP host left unset => invites won't send) ---
    { name = "CAMUNDA_MODELER_MAIL_FROMADDRESS", value = "changeme@example.com" },

    # --- OIDC / Management Identity (provider-agnostic local.oidc interface) ---
    # Always GENERIC, including for the bundled Keycloak: that Keycloak is wired as a
    # plain OIDC provider (the realm import carries no roles or groups), so the Identity
    # SDK must resolve permissions through Management Identity's RBAC model instead of
    # from realm roles. Declaring KEYCLOAK makes the SDK look for realm roles that do not
    # exist, which yields an empty permission set and a blanket
    # `hasAccessToOrganization` denial — Web Modeler authenticates but every project
    # call fails (403 on the management API, 404 on org-scoped resources).
    { name = "CAMUNDA_IDENTITY_TYPE", value = "GENERIC" },
    # Backend call to Management Identity (org/roles): use the internal Service
    # Connect address, not the public ALB URL — Identity's ALB rule is opt-in and
    # off by default, so the public /identity path is not reachable.
    { name = "CAMUNDA_IDENTITY_BASEURL", value = "http://${module.management_identity[0].identity_service_connect}:8084" },
    { name = "CAMUNDA_IDENTITY_ISSUER", value = local.oidc.issuer_uri },
    # Backend metadata/JWKS fetches use the in-VPC address, which is what makes
    # authorization work on a freshly started task; see local.oidc_issuer_backend_uri.
    { name = "CAMUNDA_IDENTITY_ISSUERBACKENDURL", value = local.oidc_issuer_backend_uri },
    # Spring's resource server keeps the public issuer: it validates the token's `iss`.
    { name = "SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUERURI", value = local.oidc.issuer_uri },
    { name = "CAMUNDA_MODELER_OAUTH2_CLIENT_ID", value = local.oidc.webmodeler.client_id },
    { name = "CAMUNDA_MODELER_SECURITY_JWT_AUDIENCE_INTERNAL_API", value = local.oidc.webmodeler.audience_internal },
    { name = "CAMUNDA_MODELER_SECURITY_JWT_AUDIENCE_PUBLIC_API", value = local.oidc.webmodeler.audience_public },
    # Public root URL for OAuth redirects (matches the web-modeler client's ALB redirect-uri).
    { name = "CAMUNDA_MODELER_SERVER_URL", value = "${local.alb_base_url}${local.camunda_hub_context_path}" },
    # Match the rest of the stack's HTTP-only demo posture: without an ALB cert the
    # app must not force an HTTP->HTTPS redirect (there is no HTTPS listener yet).
    { name = "CAMUNDA_MODELER_SERVER_HTTPSONLY", value = local.alb_https_enabled ? "true" : "false" },

    # --- Browser-side Pusher (public ALB host + <context>-ws route) ---
    { name = "CAMUNDA_MODELER_PUSHER_CLIENT_HOST", value = aws_lb.main.dns_name },
    { name = "CAMUNDA_MODELER_PUSHER_CLIENT_PORT", value = local.alb_https_enabled ? "443" : "80" },
    { name = "CAMUNDA_MODELER_PUSHER_CLIENT_PATH", value = "${local.camunda_hub_context_path}-ws" },
    { name = "CAMUNDA_MODELER_PUSHER_CLIENT_FORCETLS", value = local.alb_https_enabled ? "true" : "false" },

    # --- Orchestration cluster wiring (internal Service Connect; user bearer token) ---
    # Whole cluster definition including the Console health (readiness) URL; see the
    # local above for why this is JSON rather than flat CAMUNDA_MODELER_CLUSTERS_0_* vars.
    { name = "SPRING_APPLICATION_JSON", value = local.camunda_hub_clusters_json },
  ]

  extra_task_role_attachments = [
    aws_iam_policy.rds_db_connect_camunda_hub[0].arn,
  ]
}
