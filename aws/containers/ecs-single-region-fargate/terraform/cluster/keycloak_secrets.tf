################################################################
#              Bundled Keycloak / realm secrets                #
################################################################

# All secrets here belong to the bundled Keycloak provider and are created only
# when it is deployed (local.deploy_bundled_keycloak = OIDC enabled with no external
# provider). With an external OIDC provider these are not created; client secrets
# then come from var.external_oidc. The client secrets below are embedded into the
# Keycloak realm import (keycloak_realm.tf) and consumed by the components via
# local.oidc, so the components never reference these resources directly.

resource "random_password" "keycloak_db_password" {
  count            = local.deploy_bundled_keycloak ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "keycloak_db_password" {
  count                   = local.deploy_bundled_keycloak ? 1 : 0
  name                    = "${var.prefix}-oc1-keycloak-db-password"
  description             = "Password for the Keycloak Aurora PostgreSQL role (KC_DB_PASSWORD)"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}

resource "aws_secretsmanager_secret_version" "keycloak_db_password" {
  count         = local.deploy_bundled_keycloak ? 1 : 0
  secret_id     = aws_secretsmanager_secret.keycloak_db_password[0].id
  secret_string = random_password.keycloak_db_password[0].result
}

resource "random_password" "keycloak_admin_password" {
  count            = local.deploy_bundled_keycloak ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%^()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "keycloak_admin_password" {
  count                   = local.deploy_bundled_keycloak ? 1 : 0
  name                    = "${var.prefix}-oc1-keycloak-admin-password"
  description             = "Keycloak bootstrap admin password (KC_BOOTSTRAP_ADMIN_PASSWORD)"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}

resource "aws_secretsmanager_secret_version" "keycloak_admin_password" {
  count         = local.deploy_bundled_keycloak ? 1 : 0
  secret_id     = aws_secretsmanager_secret.keycloak_admin_password[0].id
  secret_string = random_password.keycloak_admin_password[0].result
}

# Password for the `admin` login user defined in the camunda-platform realm import
# (the interactive login user). Same 32-char strength as the basic-auth admin, but
# excludes ${ } to stay safe if referenced through any templating layer.
resource "random_password" "realm_admin_user_password" {
  count            = local.deploy_bundled_keycloak ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#%^()-_=+[]:?"
}

resource "aws_secretsmanager_secret" "realm_admin_user_password" {
  count                   = local.deploy_bundled_keycloak ? 1 : 0
  name                    = "${var.prefix}-oc1-realm-admin-user-password"
  description             = "Password for the Keycloak camunda-platform realm 'admin' login user (embedded in the realm import)"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}

resource "aws_secretsmanager_secret_version" "realm_admin_user_password" {
  count         = local.deploy_bundled_keycloak ? 1 : 0
  secret_id     = aws_secretsmanager_secret.realm_admin_user_password[0].id
  secret_string = random_password.realm_admin_user_password[0].result
}

resource "random_password" "identity_client_secret" {
  count   = local.deploy_bundled_keycloak ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "identity_client_secret" {
  count                   = local.deploy_bundled_keycloak ? 1 : 0
  name                    = "${var.prefix}-oc1-identity-oidc-client-secret"
  description             = "Keycloak OIDC client secret for the camunda-identity client (embedded in the realm import; CAMUNDA_IDENTITY_CLIENT_SECRET)"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}

resource "aws_secretsmanager_secret_version" "identity_client_secret" {
  count         = local.deploy_bundled_keycloak ? 1 : 0
  secret_id     = aws_secretsmanager_secret.identity_client_secret[0].id
  secret_string = random_password.identity_client_secret[0].result
}

# --- core component client secrets (embedded in the realm import) ---
# orchestration, connectors, and camunda-identity are the clients the realm import
# defines, so their secrets are always created alongside the bundled Keycloak.

resource "random_password" "orchestration_oidc_client_secret" {
  count   = local.deploy_bundled_keycloak ? 1 : 0
  length  = 32
  special = false
}
resource "aws_secretsmanager_secret" "orchestration_oidc_client_secret" {
  count                   = local.deploy_bundled_keycloak ? 1 : 0
  name                    = "${var.prefix}-oc1-orchestration-oidc-client-secret"
  description             = "Keycloak OIDC client secret for the orchestration client"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}
resource "aws_secretsmanager_secret_version" "orchestration_oidc_client_secret" {
  count         = local.deploy_bundled_keycloak ? 1 : 0
  secret_id     = aws_secretsmanager_secret.orchestration_oidc_client_secret[0].id
  secret_string = random_password.orchestration_oidc_client_secret[0].result
}

resource "random_password" "connectors_oidc_client_secret" {
  count   = local.deploy_bundled_keycloak ? 1 : 0
  length  = 32
  special = false
}
resource "aws_secretsmanager_secret" "connectors_oidc_client_secret" {
  count                   = local.deploy_bundled_keycloak ? 1 : 0
  name                    = "${var.prefix}-oc1-connectors-oidc-client-secret"
  description             = "Keycloak OIDC client secret for the connectors client"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}
resource "aws_secretsmanager_secret_version" "connectors_oidc_client_secret" {
  count         = local.deploy_bundled_keycloak ? 1 : 0
  secret_id     = aws_secretsmanager_secret.connectors_oidc_client_secret[0].id
  secret_string = random_password.connectors_oidc_client_secret[0].result
}
