# Temporary AWS Cognito User Pool for testing purposes
# This module creates a Cognito User Pool with required configuration for Camunda Platform

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  resource_prefix = var.resource_prefix != "" ? var.resource_prefix : "camunda-test"

  # Domain prefix - cannot contain "cognito" (reserved word)
  domain_prefix = replace(local.resource_prefix, "cognito", "cgnto")

  # Callback URLs for Camunda components
  callback_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/auth/login-callback",
    "https://${var.domain_name}/optimize/api/authentication/callback",
    "https://${var.domain_name}/sso-callback",
    "https://${var.domain_name}/console/",
    "https://${var.domain_name}/modeler/login-callback",
    "https://${var.domain_name}/connectors/login-callback"
  ] : ["http://localhost:8080/sso-callback"]

  logout_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/",
    "https://${var.domain_name}/auth/logout",
    "https://${var.domain_name}/optimize/",
    "https://${var.domain_name}/console/"
  ] : ["http://localhost:8080/"]

  common_tags = merge(var.tags, {
    "environment"        = "test"
    "purpose"            = "camunda-integration-test"
    "managed-by"         = "terraform"
    "expires-at"         = time_static.creation.rfc3339
    "cleanup-after"      = "${var.auto_cleanup_hours}h"
    "auto_cleanup_hours" = tostring(var.auto_cleanup_hours)
  })
}

# Random suffix for unique naming (Cognito domains must be globally unique)
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Track creation time for cleanup purposes
resource "time_static" "creation" {}

# Cognito User Pool
resource "aws_cognito_user_pool" "camunda" {
  name = "${local.resource_prefix}-${random_string.suffix.result}"

  # Username configuration - use email as username
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Disable self-service sign-up - only admins can create users
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  # Password policy
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # MFA configuration
  mfa_configuration = var.mfa_enabled ? "OPTIONAL" : "OFF"

  dynamic "software_token_mfa_configuration" {
    for_each = var.mfa_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email configuration (using Cognito default)
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Schema attributes
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  schema {
    name                     = "name"
    attribute_data_type      = "String"
    required                 = false
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # User pool add-ons for security
  user_pool_add_ons {
    advanced_security_mode = "AUDIT"
  }

  tags = local.common_tags
}

# Cognito User Pool Domain (for hosted UI and OIDC endpoints)
resource "aws_cognito_user_pool_domain" "camunda" {
  domain       = "${local.domain_prefix}-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.camunda.id
}

# Resource Server for Camunda scopes (M2M communication)
resource "aws_cognito_resource_server" "camunda" {
  identifier   = "camunda"
  name         = "Camunda Platform"
  user_pool_id = aws_cognito_user_pool.camunda.id

  scope {
    scope_name        = "identity"
    scope_description = "Access to Identity service"
  }

  scope {
    scope_name        = "optimize"
    scope_description = "Access to Optimize service"
  }

  scope {
    scope_name        = "orchestration"
    scope_description = "Access to Orchestration cluster"
  }

  scope {
    scope_name        = "console"
    scope_description = "Access to Console"
  }

  scope {
    scope_name        = "connectors"
    scope_description = "Access to Connectors"
  }

  scope {
    scope_name        = "webmodeler"
    scope_description = "Access to Web Modeler"
  }
}

# Identity App Client (confidential client with secret)
resource "aws_cognito_user_pool_client" "identity" {
  name         = "${local.resource_prefix}-identity"
  user_pool_id = aws_cognito_user_pool.camunda.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/auth/login-callback"
  ] : ["http://localhost:8084/auth/login-callback"]

  logout_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/auth/logout"
  ] : ["http://localhost:8084/logout"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# Optimize App Client
resource "aws_cognito_user_pool_client" "optimize" {
  name         = "${local.resource_prefix}-optimize"
  user_pool_id = aws_cognito_user_pool.camunda.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/optimize/api/authentication/callback"
  ] : ["http://localhost:8083/api/authentication/callback"]

  logout_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/optimize/"
  ] : ["http://localhost:8083/"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# Orchestration App Client (Operate/Tasklist/Zeebe)
resource "aws_cognito_user_pool_client" "orchestration" {
  name         = "${local.resource_prefix}-orchestration"
  user_pool_id = aws_cognito_user_pool.camunda.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/sso-callback"
  ] : ["http://localhost:8080/sso-callback"]

  logout_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/"
  ] : ["http://localhost:8080/"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# Console App Client (Public - no secret for SPA)
resource "aws_cognito_user_pool_client" "console" {
  count = var.enable_console ? 1 : 0

  name         = "${local.resource_prefix}-console"
  user_pool_id = aws_cognito_user_pool.camunda.id

  generate_secret = false # Public client for SPA

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/console/"
  ] : ["http://localhost:8087/"]

  logout_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/console/"
  ] : ["http://localhost:8087/"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# Connectors App Client (M2M with client credentials)
# Needs orchestration scope to communicate with Zeebe/Orchestration API
resource "aws_cognito_user_pool_client" "connectors" {
  name         = "${local.resource_prefix}-connectors"
  user_pool_id = aws_cognito_user_pool.camunda.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.camunda.identifier}/connectors",
    "${aws_cognito_resource_server.camunda.identifier}/orchestration"
  ]

  supported_identity_providers = ["COGNITO"]

  # No user auth flows needed for M2M client
  explicit_auth_flows = []

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# WebModeler UI App Client (Public - no secret for SPA)
resource "aws_cognito_user_pool_client" "webmodeler_ui" {
  count = var.enable_webmodeler ? 1 : 0

  name         = "${local.resource_prefix}-webmodeler-ui"
  user_pool_id = aws_cognito_user_pool.camunda.id

  generate_secret = false # Public client for SPA

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/modeler/login-callback"
  ] : ["http://localhost:8070/login-callback"]

  logout_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/modeler/"
  ] : ["http://localhost:8070/"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# WebModeler API App Client (confidential - M2M only)
resource "aws_cognito_user_pool_client" "webmodeler_api" {
  count = var.enable_webmodeler ? 1 : 0

  name         = "${local.resource_prefix}-webmodeler-api"
  user_pool_id = aws_cognito_user_pool.camunda.id

  generate_secret = true

  # M2M client - only client_credentials flow (cannot be combined with code/implicit)
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.camunda.identifier}/webmodeler"
  ]

  supported_identity_providers = ["COGNITO"]

  # No user auth flows needed for M2M client
  explicit_auth_flows = []

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# Create test user if requested
resource "aws_cognito_user" "test" {
  count = var.create_test_user ? 1 : 0

  user_pool_id = aws_cognito_user_pool.camunda.id
  username     = var.test_user_name

  attributes = {
    email          = var.test_user_name
    email_verified = true
  }

  # Set permanent password (no forced change on first login)
  password = var.test_user_password

  # SUPPRESS = don't send welcome email, user is created in CONFIRMED status
  # This avoids FORCE_CHANGE_PASSWORD status
  message_action = "SUPPRESS"

  lifecycle {
    ignore_changes = [password]
  }
}

# Cleanup marker for tracking
resource "null_resource" "cleanup_marker" {
  triggers = {
    created_at   = time_static.creation.rfc3339
    expires_at   = timeadd(time_static.creation.rfc3339, "${var.auto_cleanup_hours}h")
    user_pool_id = aws_cognito_user_pool.camunda.id
  }
}
