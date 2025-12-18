################################################################
#                          ECS Secrets                         #
################################################################

# This file wires selected sensitive environment variables through
# ECS task definition `secrets` (Secrets Manager) instead of plaintext
# `environment` values.

resource "random_password" "admin_user_password" {
  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}:?"
}

resource "random_password" "connectors_user_password" {
  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "orchestration_admin_user_password" {
  name                    = "${var.prefix}-oc1-admin-user-password"
  description             = "Password for CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD (admin user)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "orchestration_admin_user_password" {
  secret_id     = aws_secretsmanager_secret.orchestration_admin_user_password.id
  secret_string = random_password.admin_user_password.result
}

resource "aws_secretsmanager_secret" "connectors_client_auth_password" {
  name                    = "${var.prefix}-oc1-connectors-client-auth-password"
  description             = "Password for CAMUNDA_CLIENT_AUTH_PASSWORD (connectors basic auth)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "connectors_client_auth_password" {
  secret_id     = aws_secretsmanager_secret.connectors_client_auth_password.id
  secret_string = random_password.connectors_user_password.result
}
