################################################################
#                     App User Passwords                       #
################################################################
# These passwords are generated here (not in the infra layer) because
# they belong to the Camunda application lifecycle, not the platform.
# The Aurora admin password is managed in the infra layer.
#
# recovery_window_in_days = 0 is intentional for a reference/demo deployment.
# Set it to >= 7 in production.

resource "random_password" "admin_user_password" {
  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

resource "random_password" "connectors_user_password" {
  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

################################################################
#                  Region 0 Secrets                            #
################################################################

resource "aws_secretsmanager_secret" "admin_user_password_region_0" {
  name                    = "${local.prefix_region_0}-oc-admin-user-password"
  description             = "Password for Camunda admin user (${local.prefix_region_0})"
  recovery_window_in_days = 0
  kms_key_id              = local.infra.region_0_secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "admin_user_password_region_0" {
  secret_id     = aws_secretsmanager_secret.admin_user_password_region_0.id
  secret_string = random_password.admin_user_password.result
}

resource "aws_secretsmanager_secret" "connectors_password_region_0" {
  name                    = "${local.prefix_region_0}-oc-connectors-password"
  description             = "Password for Connectors basic auth (${local.prefix_region_0})"
  recovery_window_in_days = 0
  kms_key_id              = local.infra.region_0_secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "connectors_password_region_0" {
  secret_id     = aws_secretsmanager_secret.connectors_password_region_0.id
  secret_string = random_password.connectors_user_password.result
}

################################################################
#                  Region 1 Secrets                            #
################################################################

resource "aws_secretsmanager_secret" "admin_user_password_region_1" {
  provider = aws.accepter

  name                    = "${local.prefix_region_1}-oc-admin-user-password"
  description             = "Password for Camunda admin user (${local.prefix_region_1})"
  recovery_window_in_days = 0
  kms_key_id              = local.infra.region_1_secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "admin_user_password_region_1" {
  provider = aws.accepter

  secret_id     = aws_secretsmanager_secret.admin_user_password_region_1.id
  secret_string = random_password.admin_user_password.result
}

resource "aws_secretsmanager_secret" "connectors_password_region_1" {
  provider = aws.accepter

  name                    = "${local.prefix_region_1}-oc-connectors-password"
  description             = "Password for Connectors basic auth (${local.prefix_region_1})"
  recovery_window_in_days = 0
  kms_key_id              = local.infra.region_1_secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "connectors_password_region_1" {
  provider = aws.accepter

  secret_id     = aws_secretsmanager_secret.connectors_password_region_1.id
  secret_string = random_password.connectors_user_password.result
}

################################################################
#              Registry Credentials                            #
################################################################
# Created only when registry_username is provided. The secret is in DockerConfigJson
# format expected by ECS repositoryCredentials.

resource "aws_secretsmanager_secret" "registry_credentials_region_0" {
  count = var.registry_username != "" ? 1 : 0

  name                    = "${local.prefix_region_0}-oc-registry-credentials"
  description             = "Docker registry credentials for private Camunda image (${local.prefix_region_0})"
  recovery_window_in_days = 0
  kms_key_id              = local.infra.region_0_secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "registry_credentials_region_0" {
  count = var.registry_username != "" ? 1 : 0

  secret_id = aws_secretsmanager_secret.registry_credentials_region_0[0].id
  secret_string = jsonencode({
    username = var.registry_username
    password = var.registry_password
  })
}

resource "aws_secretsmanager_secret" "registry_credentials_region_1" {
  count    = var.registry_username != "" ? 1 : 0
  provider = aws.accepter

  name                    = "${local.prefix_region_1}-oc-registry-credentials"
  description             = "Docker registry credentials for private Camunda image (${local.prefix_region_1})"
  recovery_window_in_days = 0
  kms_key_id              = local.infra.region_1_secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "registry_credentials_region_1" {
  count    = var.registry_username != "" ? 1 : 0
  provider = aws.accepter

  secret_id = aws_secretsmanager_secret.registry_credentials_region_1[0].id
  secret_string = jsonencode({
    username = var.registry_username
    password = var.registry_password
  })
}
