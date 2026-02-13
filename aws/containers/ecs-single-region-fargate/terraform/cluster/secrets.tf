################################################################
#                          ECS Secrets                         #
################################################################

# This file wires selected sensitive environment variables through
# ECS task definition `secrets` (Secrets Manager) instead of plaintext
# `environment` values.

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

resource "random_password" "db_admin_password" {
  count = var.db_admin_password == "" ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

locals {
  db_admin_password_effective = var.db_admin_password != "" ? var.db_admin_password : random_password.db_admin_password[0].result
}

resource "aws_secretsmanager_secret" "db_admin_password" {
  name                    = "${var.prefix}-db-admin-password"
  description             = "Admin password for the Aurora PostgreSQL cluster (${var.prefix})"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}

resource "aws_secretsmanager_secret_version" "db_admin_password" {
  secret_id     = aws_secretsmanager_secret.db_admin_password.id
  secret_string = local.db_admin_password_effective
}

resource "aws_secretsmanager_secret" "orchestration_admin_user_password" {
  name                    = "${var.prefix}-oc1-admin-user-password"
  description             = "Password for CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD (admin user)"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}

resource "aws_secretsmanager_secret_version" "orchestration_admin_user_password" {
  secret_id     = aws_secretsmanager_secret.orchestration_admin_user_password.id
  secret_string = random_password.admin_user_password.result
}

resource "aws_secretsmanager_secret" "connectors_client_auth_password" {
  name                    = "${var.prefix}-oc1-connectors-client-auth-password"
  description             = "Password for CAMUNDA_CLIENT_AUTH_PASSWORD (connectors basic auth)"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}

resource "aws_secretsmanager_secret_version" "connectors_client_auth_password" {
  secret_id     = aws_secretsmanager_secret.connectors_client_auth_password.id
  secret_string = random_password.connectors_user_password.result
}
