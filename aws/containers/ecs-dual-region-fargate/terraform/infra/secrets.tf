################################################################
#                  DB Admin Password                           #
################################################################
# Only the Aurora admin password lives in this layer — it is needed by the
# aurora-global module at apply time (master_password). App user passwords
# (admin, connectors) are generated and stored in the camunda layer.
#
# recovery_window_in_days = 0 is intentional for a reference/demo deployment.
# Set it to >= 7 in production.

locals {
  db_admin_password_effective = var.db_admin_password != "" ? var.db_admin_password : random_password.db_admin_password[0].result
}

resource "random_password" "db_admin_password" {
  count = var.db_admin_password == "" ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

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
