# Azure AD / EntraID Configuration for Camunda Platform

# Data source to get current Azure AD tenant information
data "azuread_client_config" "current" {}

# Identity Application
resource "azuread_application" "identity" {
  display_name = "${local.resource_prefix}-identity"
  owners       = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  web {
    redirect_uris = var.domain_name != "" ? [
      "https://${var.domain_name}/auth/login-callback"
    ] : ["http://localhost:8084/auth/login-callback"]
  }

  implicit_grant {
    access_token_issuance_enabled = true
    id_token_issuance_enabled     = true
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

resource "azuread_application_password" "identity" {
  application_id = azuread_application.identity.id
  display_name   = "Identity Client Secret"
}

# Optimize Application
resource "azuread_application" "optimize" {
  display_name = "${local.resource_prefix}-optimize"
  owners       = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  web {
    redirect_uris = var.domain_name != "" ? [
      "https://${var.domain_name}/api/authentication/callback"
    ] : ["http://localhost:8083/api/authentication/callback"]
  }

  implicit_grant {
    access_token_issuance_enabled = true
    id_token_issuance_enabled     = true
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

resource "azuread_application_password" "optimize" {
  application_id = azuread_application.optimize.id
  display_name   = "Optimize Client Secret"
}

# Orchestration Cluster Application (Operate)
resource "azuread_application" "orchestration" {
  display_name = "${local.resource_prefix}-orchestration-cluster"
  owners       = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  web {
    redirect_uris = var.domain_name != "" ? [
      "https://${var.domain_name}/sso-callback"
    ] : ["http://localhost:8080/sso-callback"]
  }

  implicit_grant {
    access_token_issuance_enabled = true
    id_token_issuance_enabled     = true
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

resource "azuread_application_password" "orchestration" {
  application_id = azuread_application.orchestration.id
  display_name   = "Orchestration Cluster Client Secret"
}

# Console Application (Single Page Application)
resource "azuread_application" "console" {
  display_name = "${local.resource_prefix}-console"
  owners       = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  spa {
    redirect_uris = var.domain_name != "" ? [
      "https://${var.domain_name}/"
    ] : ["http://localhost:8087/"]
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

# Console is a Single Page Application and does not require a client secret

# WebModeler UI Application (Single Page Application - optional)
resource "azuread_application" "webmodeler_ui" {
  count        = var.enable_webmodeler ? 1 : 0
  display_name = "${local.resource_prefix}-webmodeler-ui"
  owners       = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  spa {
    redirect_uris = var.domain_name != "" ? [
      "https://${var.domain_name}/login-callback"
    ] : ["http://localhost:8070/login-callback"]
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

# WebModeler API Application (Web - optional)
resource "azuread_application" "webmodeler_api" {
  count        = var.enable_webmodeler ? 1 : 0
  display_name = "${local.resource_prefix}-webmodeler-api"
  owners       = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

resource "azuread_application_password" "webmodeler_api" {
  count          = var.enable_webmodeler ? 1 : 0
  application_id = azuread_application.webmodeler_api[0].id
  display_name   = "WebModeler API Client Secret"
}
