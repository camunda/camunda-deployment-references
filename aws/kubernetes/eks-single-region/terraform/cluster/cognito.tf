# Amazon Cognito Configuration for Camunda Platform on AWS EKS
#
# This module creates a Cognito User Pool and App Clients for Camunda Platform authentication.
# Cognito replaces the default embedded Keycloak with a fully managed AWS service.
#
# Benefits of using Cognito:
# - Fully managed by AWS (no maintenance)
# - Native AWS integration (IAM, CloudWatch, etc.)
# - Built-in MFA, password policies, and security features
# - Supports federation with external IdPs (SAML, OIDC, social)

locals {
  cognito_resource_prefix = var.cognito_resource_prefix != "" ? var.cognito_resource_prefix : local.eks_cluster_name
  cognito_callback_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/auth/login-callback",
    "https://${var.domain_name}/optimize/api/authentication/callback",
    "https://${var.domain_name}/sso-callback",
    "https://${var.domain_name}/console/",
    "https://${var.domain_name}/modeler/login-callback",
    "https://${var.domain_name}/connectors/login-callback"
  ] : ["http://localhost:8080/sso-callback"]
  cognito_logout_urls = var.domain_name != "" ? [
    "https://${var.domain_name}/",
    "https://${var.domain_name}/auth/logout",
    "https://${var.domain_name}/optimize/",
    "https://${var.domain_name}/console/"
  ] : ["http://localhost:8080/"]
}

# Cognito User Pool
resource "aws_cognito_user_pool" "camunda" {
  count = var.enable_cognito ? 1 : 0
  name  = "${local.cognito_resource_prefix}-camunda"

  # Username configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # MFA configuration (optional but recommended)
  mfa_configuration = var.cognito_mfa_enabled ? "OPTIONAL" : "OFF"

  dynamic "software_token_mfa_configuration" {
    for_each = var.cognito_mfa_enabled ? [1] : []
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

  # Email configuration
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

  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "AUDIT"
  }

  tags = local.eks_tags
}

# Cognito User Pool Domain (for hosted UI)
resource "aws_cognito_user_pool_domain" "camunda" {
  count        = var.enable_cognito ? 1 : 0
  domain       = "${local.cognito_resource_prefix}-camunda"
  user_pool_id = aws_cognito_user_pool.camunda[0].id
}

# Resource Server for Camunda scopes
resource "aws_cognito_resource_server" "camunda" {
  count        = var.enable_cognito ? 1 : 0
  identifier   = "camunda"
  name         = "Camunda Platform"
  user_pool_id = aws_cognito_user_pool.camunda[0].id

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

# Identity App Client
resource "aws_cognito_user_pool_client" "identity" {
  count        = var.enable_cognito ? 1 : 0
  name         = "${local.cognito_resource_prefix}-identity"
  user_pool_id = aws_cognito_user_pool.camunda[0].id

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
    "ALLOW_USER_SRP_AUTH"
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
  count        = var.enable_cognito ? 1 : 0
  name         = "${local.cognito_resource_prefix}-optimize"
  user_pool_id = aws_cognito_user_pool.camunda[0].id

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
    "ALLOW_USER_SRP_AUTH"
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
  count        = var.enable_cognito ? 1 : 0
  name         = "${local.cognito_resource_prefix}-orchestration"
  user_pool_id = aws_cognito_user_pool.camunda[0].id

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
    "ALLOW_USER_SRP_AUTH"
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
  count        = var.enable_cognito && var.enable_console ? 1 : 0
  name         = "${local.cognito_resource_prefix}-console"
  user_pool_id = aws_cognito_user_pool.camunda[0].id

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
    "ALLOW_USER_SRP_AUTH"
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

# Connectors App Client
resource "aws_cognito_user_pool_client" "connectors" {
  count        = var.enable_cognito ? 1 : 0
  name         = "${local.cognito_resource_prefix}-connectors"
  user_pool_id = aws_cognito_user_pool.camunda[0].id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "client_credentials"]
  allowed_oauth_scopes = [
    "email", "openid", "profile",
    "${aws_cognito_resource_server.camunda[0].identifier}/connectors"
  ]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
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

# WebModeler UI App Client (Public - no secret for SPA)
resource "aws_cognito_user_pool_client" "webmodeler_ui" {
  count        = var.enable_cognito && var.enable_webmodeler ? 1 : 0
  name         = "${local.cognito_resource_prefix}-webmodeler-ui"
  user_pool_id = aws_cognito_user_pool.camunda[0].id

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
    "ALLOW_USER_SRP_AUTH"
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

# WebModeler API App Client
resource "aws_cognito_user_pool_client" "webmodeler_api" {
  count        = var.enable_cognito && var.enable_webmodeler ? 1 : 0
  name         = "${local.cognito_resource_prefix}-webmodeler-api"
  user_pool_id = aws_cognito_user_pool.camunda[0].id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "client_credentials"]
  allowed_oauth_scopes = [
    "email", "openid", "profile",
    "${aws_cognito_resource_server.camunda[0].identifier}/webmodeler"
  ]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
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

# Create initial admin user
resource "aws_cognito_user" "admin" {
  count        = var.enable_cognito && var.cognito_create_admin_user ? 1 : 0
  user_pool_id = aws_cognito_user_pool.camunda[0].id
  username     = var.identity_initial_user_email

  attributes = {
    email          = var.identity_initial_user_email
    email_verified = true
  }

  # User will need to set password on first login
  temporary_password = var.cognito_admin_temporary_password

  lifecycle {
    ignore_changes = [temporary_password]
  }
}
