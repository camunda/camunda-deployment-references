# Management Identity of the management plane: the permission model that Camunda Hub resolves
# its authorization through. It signs in against the OIDC provider (or yours) and keeps its own
# database. With enable_hub_authorization it also declares the roles Camunda Hub asks about.

data "aws_region" "current" {}

locals {
  identity_base_public = "${var.public_base_url}${var.context_path}"
}

resource "aws_iam_policy" "client_secret_read" {
  name        = "${var.prefix}-identity-client-secret-read"
  description = "Allow the ECS task execution role to read the Management Identity client secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.oidc.identity.client_secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = var.secrets_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "client_secret_read" {
  role       = var.task_execution_role_name
  policy_arn = aws_iam_policy.client_secret_read.arn
}

# Referenced only to order the deployment after the database exists.
resource "terraform_data" "database_ready" {
  input = var.db_seed_done
}

module "management_identity" {
  source = "../../../../modules/ecs/fargate/management-identity"

  depends_on = [terraform_data.database_ready, aws_iam_role_policy_attachment.client_secret_read]

  prefix                      = "${var.prefix}-mi"
  ecs_cluster_id              = var.ecs_cluster_id
  vpc_id                      = var.vpc_id
  vpc_private_subnets         = var.private_subnet_ids
  aws_region                  = data.aws_region.current.region
  s2s_cloudmap_namespace      = var.service_connect_namespace_arn
  log_group_name              = var.log_group_name
  ecs_task_execution_role_arn = var.task_execution_role_arn
  registry_credentials_arn    = var.registry_credentials_arn

  # The rule sits below the orchestration catch-all in priority number, and the task serves the
  # same prefix, because the load balancer forwards the path unchanged.
  alb_listener_http_webapp_arn         = var.alb_listener_http_webapp_arn
  enable_alb_http_webapp_listener_rule = true
  context_path                         = var.context_path

  service_security_group_ids = [
    var.camunda_ports_security_group_id,
    var.egress_security_group_id,
  ]

  environment_variables = concat(
    [
      # Database: its own database, IAM authentication through the AWS JDBC wrapper.
      { name = "SPRING_DATASOURCE_URL", value = var.database.jdbc_url },
      { name = "SPRING_DATASOURCE_USERNAME", value = var.database.username },
      { name = "SPRING_DATASOURCE_DRIVER_CLASS_NAME", value = "software.amazon.jdbc.Driver" },
      { name = "SERVER_PORT", value = "8084" },
      { name = "MANAGEMENT_SERVER_PORT", value = "8082" },
      { name = "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE", value = "health" },
      { name = "MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED", value = "true" },
      # Generic OIDC: Identity handles sign-in and token validation. The provider owns the clients
      # and users, so authorization is declared on the Identity side (see authorization.tf).
      { name = "SPRING_PROFILES_ACTIVE", value = "oidc" },
      { name = "CAMUNDA_IDENTITY_TYPE", value = "GENERIC" },
      # The load balancer forwards the path unchanged, so the application serves the same prefix.
      { name = "SERVER_SERVLET_CONTEXT_PATH", value = var.context_path },
      { name = "CAMUNDA_IDENTITY_BASE_URL", value = local.identity_base_public },
      { name = "CAMUNDA_IDENTITY_ISSUER", value = var.oidc.issuer_uri },
      # Server-side metadata and key set fetches use the address inside the VPC.
      { name = "CAMUNDA_IDENTITY_ISSUER_BACKEND_URL", value = var.oidc.issuer_backend_uri },
      { name = "CAMUNDA_IDENTITY_CLIENT_ID", value = var.oidc.identity.client_id },
      { name = "CAMUNDA_IDENTITY_AUDIENCE", value = var.oidc.identity.audience },
    ],
    local.bootstrap_env,
    local.authorization_env,
  )

  secrets = [
    { name = "CAMUNDA_IDENTITY_CLIENT_SECRET", valueFrom = var.oidc.identity.client_secret_arn },
  ]

  task_desired_count          = 1
  extra_task_role_attachments = [var.database.connect_policy_arn]
  wait_for_steady_state       = true
}
