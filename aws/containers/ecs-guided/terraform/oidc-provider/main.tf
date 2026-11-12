# The OIDC provider of the management plane, deployed on ECS. The first implementation is
# the one the single-region reference ships. It imports the realm below when it starts for
# the first time, and the rest of the platform consumes it exactly like an OIDC provider that
# you run yourself: through the issuer and the clients in the outputs.

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.prefix}-oidc-provider-secrets-read"
  description = "Allow the ECS task execution role to read the secrets of the OIDC provider"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.bootstrap_admin.arn,
          aws_secretsmanager_secret.realm_import.arn,
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

resource "aws_iam_role_policy_attachment" "secrets_read" {
  role       = var.task_execution_role_name
  policy_arn = aws_iam_policy.secrets_read.arn
}

data "aws_region" "current" {}

# Referenced only to order the deployment after the database exists.
resource "terraform_data" "database_ready" {
  input = var.db_seed_done
}

module "oidc_provider" {
  source = "../../../../modules/ecs/fargate/keycloak"

  depends_on = [terraform_data.database_ready, aws_iam_role_policy_attachment.secrets_read]

  prefix                      = "${var.prefix}-oidc"
  ecs_cluster_id              = var.ecs_cluster_id
  vpc_id                      = var.vpc_id
  vpc_private_subnets         = var.private_subnet_ids
  aws_region                  = data.aws_region.current.region
  s2s_cloudmap_namespace      = var.service_connect_namespace_arn
  log_group_name              = var.log_group_name
  ecs_task_execution_role_arn = var.task_execution_role_arn
  registry_credentials_arn    = var.registry_credentials_arn

  service_connect_dns_name = var.service_connect_name

  # The browser reaches the provider through the load balancer for the login redirect.
  alb_listener_http_webapp_arn         = var.alb_listener_http_webapp_arn
  enable_alb_http_webapp_listener_rule = true

  service_security_group_ids = [
    var.camunda_ports_security_group_id,
    var.egress_security_group_id,
  ]

  environment_variables = concat(
    [
      { name = "KC_DB", value = "postgres" },
      { name = "KC_DB_URL", value = var.database.jdbc_url },
      { name = "KC_DB_USERNAME", value = var.database.username },
      { name = "KC_BOOTSTRAP_ADMIN_USERNAME", value = "admin" },
      { name = "KC_HTTP_ENABLED", value = "true" },
      { name = "KC_HTTP_PORT", value = "18080" },
      { name = "KC_HTTP_RELATIVE_PATH", value = "/auth" },
      { name = "KC_HEALTH_ENABLED", value = "true" },
      # The frontend URL, and so the token issuer, follows the request host: every actor reaches
      # the provider through the load balancer, so the issuer is consistently its URL.
      { name = "KC_HOSTNAME_STRICT", value = "false" },
      { name = "KC_TRANSACTION_XA_ENABLED", value = "false" },
      # One instance: use the local cache, so that a rolling deployment does not try to form a
      # cluster on ports that are not open between the tasks.
      { name = "KC_CACHE", value = "local" },
    ],
    # Behind TLS, trust the forwarded headers so the provider sees HTTPS.
    local.https_enabled ? [{ name = "KC_PROXY_HEADERS", value = "xforwarded" }] : [],
  )

  secrets = [
    { name = "KC_DB_PASSWORD", valueFrom = var.database.password_secret_arn },
    { name = "KC_BOOTSTRAP_ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.bootstrap_admin.arn },
    { name = "KEYCLOAK_REALM_IMPORT_JSON", valueFrom = aws_secretsmanager_secret.realm_import.arn },
  ]

  enable_realm_import   = true
  task_desired_count    = 1
  wait_for_steady_state = true
}
