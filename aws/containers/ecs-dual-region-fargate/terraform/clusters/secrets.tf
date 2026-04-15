################################################################
#                     Shared Passwords                         #
################################################################
# recovery_window_in_days = 0 is used throughout this file so that
# `terraform destroy` can immediately delete secrets without waiting
# for the default 30-day recovery window. This is intentional for a
# reference/demo deployment. Set it to >= 7 in production.
#

locals {
  db_admin_password_effective = var.db_admin_password != "" ? var.db_admin_password : random_password.db_admin_password[0].result
}

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

################################################################
#                  Region 0 Secrets                            #
################################################################

resource "aws_secretsmanager_secret" "db_admin_password_region_0" {
  name                    = "${local.prefix_region_0}-db-admin-password"
  description             = "Admin password for Aurora PostgreSQL (${local.prefix_region_0})"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_region_0
}

resource "aws_secretsmanager_secret_version" "db_admin_password_region_0" {
  secret_id     = aws_secretsmanager_secret.db_admin_password_region_0.id
  secret_string = local.db_admin_password_effective
}

resource "aws_secretsmanager_secret" "admin_user_password_region_0" {
  name                    = "${local.prefix_region_0}-oc-admin-user-password"
  description             = "Password for Camunda admin user (${local.prefix_region_0})"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_region_0
}

resource "aws_secretsmanager_secret_version" "admin_user_password_region_0" {
  secret_id     = aws_secretsmanager_secret.admin_user_password_region_0.id
  secret_string = random_password.admin_user_password.result
}

resource "aws_secretsmanager_secret" "connectors_password_region_0" {
  name                    = "${local.prefix_region_0}-oc-connectors-password"
  description             = "Password for Connectors basic auth (${local.prefix_region_0})"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_region_0
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
  kms_key_id              = local.secrets_kms_key_arn_region_1
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
  kms_key_id              = local.secrets_kms_key_arn_region_1
}

resource "aws_secretsmanager_secret_version" "connectors_password_region_1" {
  provider = aws.accepter

  secret_id     = aws_secretsmanager_secret.connectors_password_region_1.id
  secret_string = random_password.connectors_user_password.result
}
