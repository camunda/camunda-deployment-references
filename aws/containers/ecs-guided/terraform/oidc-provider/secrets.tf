# Secrets of the OIDC provider and of the clients it defines. The client secrets are embedded
# in the realm import and published by ARN: the components read them from Secrets Manager.

locals {
  password_chars = "!#%^()-_=+[]:?"
}

resource "random_password" "bootstrap_admin" {
  length           = 32
  special          = true
  override_special = local.password_chars
}

resource "aws_secretsmanager_secret" "bootstrap_admin" {
  name                    = "${var.prefix}-oidc-provider-bootstrap-admin-password"
  description             = "Bootstrap administrator password of the OIDC provider"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "bootstrap_admin" {
  secret_id     = aws_secretsmanager_secret.bootstrap_admin.id
  secret_string = random_password.bootstrap_admin.result
}

# The interactive login user of the realm (the platform administrator).
resource "random_password" "realm_admin_user" {
  length           = 32
  special          = true
  override_special = local.password_chars
}

resource "aws_secretsmanager_secret" "realm_admin_user" {
  name                    = "${var.prefix}-oidc-provider-admin-user-password"
  description             = "Password of the realm login user ${var.admin_username}"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "realm_admin_user" {
  secret_id     = aws_secretsmanager_secret.realm_admin_user.id
  secret_string = random_password.realm_admin_user.result
}

# One orchestration client and one connectors client per cluster, plus the Management Identity client.
resource "random_password" "orchestration_client" {
  for_each = var.clusters

  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "orchestration_client" {
  for_each = var.clusters

  name                    = "${var.prefix}-oidc-orchestration-${each.key}-client-secret"
  description             = "Client secret of the orchestration client of cluster ${each.key}"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "orchestration_client" {
  for_each = var.clusters

  secret_id     = aws_secretsmanager_secret.orchestration_client[each.key].id
  secret_string = random_password.orchestration_client[each.key].result
}

resource "random_password" "connectors_client" {
  for_each = var.clusters

  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "connectors_client" {
  for_each = var.clusters

  name                    = "${var.prefix}-oidc-connectors-${each.key}-client-secret"
  description             = "Client secret of the connectors client of cluster ${each.key}"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "connectors_client" {
  for_each = var.clusters

  secret_id     = aws_secretsmanager_secret.connectors_client[each.key].id
  secret_string = random_password.connectors_client[each.key].result
}

resource "random_password" "identity_client" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "identity_client" {
  name                    = "${var.prefix}-oidc-identity-client-secret"
  description             = "Client secret of the Management Identity client"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "identity_client" {
  secret_id     = aws_secretsmanager_secret.identity_client.id
  secret_string = random_password.identity_client.result
}
