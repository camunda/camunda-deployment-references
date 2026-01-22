# Temporary EntraID (Azure AD) for testing purposes
# This module creates an Azure AD App Registration with required configuration for Camunda Platform

terraform {
  required_version = ">= 1.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

data "azuread_client_config" "current" {}

locals {
  resource_prefix = var.resource_prefix != "" ? var.resource_prefix : "camunda-test"

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
}

# Random suffix for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Azure AD Application Registration
resource "azuread_application" "camunda" {
  display_name = "${local.resource_prefix}-${random_string.suffix.result}"
  owners       = [data.azuread_client_config.current.object_id]

  # Sign-in audience (single tenant for test isolation)
  sign_in_audience = "AzureADMyOrg"

  # Web platform configuration
  web {
    redirect_uris = local.callback_urls
    logout_url    = local.logout_urls[0]

    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }

  # Required resource access (Microsoft Graph)
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }

    resource_access {
      id   = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0" # email
      type = "Scope"
    }

    resource_access {
      id   = "14dad69e-099b-42c9-810b-d002981feec1" # profile
      type = "Scope"
    }

    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type = "Scope"
    }
  }

  # Optional claims for tokens
  optional_claims {
    id_token {
      name                  = "email"
      essential             = true
      additional_properties = []
    }

    id_token {
      name                  = "preferred_username"
      essential             = false
      additional_properties = []
    }

    access_token {
      name                  = "email"
      essential             = true
      additional_properties = []
    }
  }

  # Group membership claims
  group_membership_claims = ["SecurityGroup"]

  tags = [
    "environment:test",
    "purpose:camunda-integration-test",
    "managed-by:terraform"
  ]
}

# Service Principal for the application
resource "azuread_service_principal" "camunda" {
  client_id                    = azuread_application.camunda.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  tags = [
    "environment:test",
    "purpose:camunda-integration-test"
  ]
}

# Client secret for Identity component
resource "azuread_application_password" "identity" {
  application_id = azuread_application.camunda.id
  display_name   = "identity-client-secret"

  end_date_relative = var.secret_validity_hours != null ? "${var.secret_validity_hours}h" : "720h" # 30 days default
}

# Client secret for Optimize component
resource "azuread_application_password" "optimize" {
  application_id = azuread_application.camunda.id
  display_name   = "optimize-client-secret"

  end_date_relative = var.secret_validity_hours != null ? "${var.secret_validity_hours}h" : "720h"
}

# Client secret for Orchestration
resource "azuread_application_password" "orchestration" {
  application_id = azuread_application.camunda.id
  display_name   = "orchestration-client-secret"

  end_date_relative = var.secret_validity_hours != null ? "${var.secret_validity_hours}h" : "720h"
}

# Client secret for Connectors
resource "azuread_application_password" "connectors" {
  application_id = azuread_application.camunda.id
  display_name   = "connectors-client-secret"

  end_date_relative = var.secret_validity_hours != null ? "${var.secret_validity_hours}h" : "720h"
}

# Client secret for Web Modeler API (if enabled)
resource "azuread_application_password" "webmodeler_api" {
  count = var.enable_webmodeler ? 1 : 0

  application_id = azuread_application.camunda.id
  display_name   = "webmodeler-api-client-secret"

  end_date_relative = var.secret_validity_hours != null ? "${var.secret_validity_hours}h" : "720h"
}

# Test user for simulating human login (optional)
data "azuread_domains" "tenant" {
  count = var.create_test_user ? 1 : 0
}

resource "azuread_user" "test" {
  count = var.create_test_user ? 1 : 0

  user_principal_name   = "${var.test_user_name}@${data.azuread_domains.tenant[0].domains[0].domain_name}"
  display_name          = "Camunda Test User"
  password              = var.test_user_password
  force_password_change = false
  mail_nickname         = var.test_user_name

  lifecycle {
    ignore_changes = [password]
  }
}

# Add marker for automatic cleanup
resource "time_static" "creation" {}

resource "null_resource" "cleanup_marker" {
  triggers = {
    created_at = time_static.creation.rfc3339
    expires_at = timeadd(time_static.creation.rfc3339, "${var.auto_cleanup_hours}h")
  }
}
