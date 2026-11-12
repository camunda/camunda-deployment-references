# Camunda Hub (Web Modeler and Console): one for the whole estate, connected to as many
# Orchestration Clusters as you list in clusters. It signs in against the OIDC provider, asks
# Management Identity for roles, and keeps its own database. It never owns a cluster: adding a
# cluster means adding an entry, not another Hub.

data "aws_region" "current" {}

locals {
  https_enabled = startswith(var.public_base_url, "https://")
  public_host   = regex("^https?://([^/]+)", var.public_base_url)[0]

  # Registered clusters, in the components schema of 8.10. Health is probed on the management
  # port: the API port serves no actuator, and the v2 API needs a bearer token that a background
  # probe does not hold. Nested lists cannot be environment variables, so the whole block is one
  # SPRING_APPLICATION_JSON value, which outranks plain environment variables: list properties
  # are not merged across sources, so the clusters are defined here and nowhere else.
  clusters_json = jsonencode({
    camunda = {
      modeler = {
        clusters = [
          for id, c in var.clusters : {
            id             = id
            name           = c.name != "" ? c.name : id
            version        = c.version
            authentication = "BEARER_TOKEN"
            authorizations = { enabled = true }
            components = [
              {
                name    = "Orchestration Cluster"
                type    = "orchestration"
                version = c.version
                urls = {
                  grpc      = c.grpc_url
                  rest      = c.rest_url
                  readiness = c.readiness_url
                }
              },
            ]
          }
        ]
      }
    }
  })

  restapi_registry_credentials_arn    = startswith(var.restapi_image, "registry.camunda.cloud/") ? var.registry_credentials_arn : ""
  websockets_registry_credentials_arn = startswith(var.websockets_image, "registry.camunda.cloud/") ? var.registry_credentials_arn : ""
}

################################################################
#                           Secrets                            #
################################################################

# The relay and the REST API share these credentials.
resource "random_password" "pusher_app_key" {
  length  = 20
  special = false
}

resource "random_password" "pusher_app_secret" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "pusher_app_key" {
  name                    = "${var.prefix}-hub-pusher-app-key"
  description             = "Camunda Hub Pusher app key (shared by the REST API and the relay)"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "pusher_app_key" {
  secret_id     = aws_secretsmanager_secret.pusher_app_key.id
  secret_string = random_password.pusher_app_key.result
}

resource "aws_secretsmanager_secret" "pusher_app_secret" {
  name                    = "${var.prefix}-hub-pusher-app-secret"
  description             = "Camunda Hub Pusher app secret (shared by the REST API and the relay)"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "pusher_app_secret" {
  secret_id     = aws_secretsmanager_secret.pusher_app_secret.id
  secret_string = random_password.pusher_app_secret.result
}

resource "aws_secretsmanager_secret" "license_key" {
  count = var.camunda_license_key != "" ? 1 : 0

  name                    = "${var.prefix}-hub-license-key"
  description             = "Camunda license key, injected as CAMUNDA_LICENSE_KEY"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "license_key" {
  count = var.camunda_license_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.license_key[0].id
  secret_string = var.camunda_license_key
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.prefix}-hub-secrets-read"
  description = "Allow the ECS task execution role to read the secrets of Camunda Hub"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = concat(
          [aws_secretsmanager_secret.pusher_app_key.arn, aws_secretsmanager_secret.pusher_app_secret.arn],
          aws_secretsmanager_secret.license_key[*].arn,
        )
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

# Referenced only to order the deployment after the database exists.
resource "terraform_data" "database_ready" {
  input = var.db_seed_done
}

################################################################
#                         Camunda Hub                          #
################################################################

module "camunda_hub" {
  source = "../../../../modules/ecs/fargate/camunda-hub"

  depends_on = [terraform_data.database_ready, aws_iam_role_policy_attachment.secrets_read]

  prefix                               = "${var.prefix}-hub"
  ecs_cluster_id                       = var.ecs_cluster_id
  vpc_id                               = var.vpc_id
  vpc_private_subnets                  = var.private_subnet_ids
  aws_region                           = data.aws_region.current.region
  s2s_cloudmap_namespace               = var.service_connect_namespace_arn
  log_group_name                       = var.log_group_name
  alb_listener_http_webapp_arn         = var.alb_listener_http_webapp_arn
  enable_alb_http_webapp_listener_rule = true

  ecs_task_execution_role_arn = var.task_execution_role_arn

  restapi_image                       = var.restapi_image
  websockets_image                    = var.websockets_image
  context_path                        = var.context_path
  restapi_registry_credentials_arn    = local.restapi_registry_credentials_arn
  websockets_registry_credentials_arn = local.websockets_registry_credentials_arn

  service_security_group_ids = [
    var.camunda_ports_security_group_id,
    var.egress_security_group_id,
  ]

  pusher_app_key_secret_arn    = aws_secretsmanager_secret.pusher_app_key.arn
  pusher_app_secret_secret_arn = aws_secretsmanager_secret.pusher_app_secret.arn
  license_secret_arn           = join("", aws_secretsmanager_secret.license_key[*].arn)

  environment_variables = [
    # Database: its own database, IAM authentication through the AWS JDBC wrapper.
    { name = "SPRING_DATASOURCE_URL", value = var.database.jdbc_url },
    { name = "SPRING_DATASOURCE_USERNAME", value = var.database.username },
    { name = "SPRING_DATASOURCE_DRIVER_CLASS_NAME", value = "software.amazon.jdbc.Driver" },

    { name = "CAMUNDA_MODELER_FEATURE_CONSOLE_ENABLED", value = "true" },
    { name = "CAMUNDA_MODELER_MAIL_FROMADDRESS", value = var.mail_from_address },

    # Generic OIDC: the provider carries no roles, so permissions come from Management Identity.
    # Declaring a provider-specific type would look for roles that do not exist and deny every
    # project call.
    { name = "CAMUNDA_IDENTITY_TYPE", value = "GENERIC" },
    # Server-side call to Management Identity, over the address inside the ECS cluster, with its
    # context path.
    { name = "CAMUNDA_IDENTITY_BASEURL", value = var.management_identity_url },
    { name = "CAMUNDA_IDENTITY_ISSUER", value = var.oidc.issuer_uri },
    { name = "CAMUNDA_IDENTITY_ISSUERBACKENDURL", value = var.oidc.issuer_backend_uri },
    # The resource server validates the public issuer, which is the issuer of the token...
    { name = "SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUERURI", value = var.oidc.issuer_uri },
    # ...and fetches the key set over the address inside the ECS cluster.
    { name = "SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWKSETURI", value = "${var.oidc.issuer_backend_uri}/protocol/openid-connect/certs" },
    { name = "CAMUNDA_MODELER_OAUTH2_CLIENT_ID", value = var.oidc.hub.client_id },
    { name = "CAMUNDA_MODELER_SECURITY_JWT_AUDIENCE_INTERNAL_API", value = var.oidc.hub.audience_internal },
    { name = "CAMUNDA_MODELER_SECURITY_JWT_AUDIENCE_PUBLIC_API", value = var.oidc.hub.audience_public },
    { name = "CAMUNDA_MODELER_SERVER_URL", value = "${var.public_base_url}${var.context_path}" },
    { name = "CAMUNDA_MODELER_SERVER_HTTPSONLY", value = local.https_enabled ? "true" : "false" },

    # The browser connects to the websocket relay through the same host as everything else.
    { name = "CAMUNDA_MODELER_PUSHER_CLIENT_HOST", value = local.public_host },
    { name = "CAMUNDA_MODELER_PUSHER_CLIENT_PORT", value = local.https_enabled ? "443" : "80" },
    { name = "CAMUNDA_MODELER_PUSHER_CLIENT_PATH", value = "${var.context_path}-ws" },
    { name = "CAMUNDA_MODELER_PUSHER_CLIENT_FORCETLS", value = local.https_enabled ? "true" : "false" },

    # The Orchestration Clusters.
    { name = "SPRING_APPLICATION_JSON", value = local.clusters_json },
  ]

  extra_task_role_attachments = [var.database.connect_policy_arn]
}
