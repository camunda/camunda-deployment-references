# EntraID Outputs for Camunda Components

output "azure_tenant_id" {
  description = "Azure AD Tenant ID"
  value       = data.azuread_client_config.current.tenant_id
}

output "domain_name" {
  description = "Domain name for Camunda deployment"
  value       = var.domain_name
}

output "identity_initial_user_email" {
  description = "Email of the initial admin user for Identity"
  value       = var.identity_initial_user_email
}

# Identity (Management Identity)
output "identity_client_id" {
  description = "Identity Application (client) ID"
  value       = azuread_application.identity.client_id
}

output "identity_client_secret" {
  description = "Identity Client Secret"
  value       = azuread_application_password.identity.value
  sensitive   = true
}

output "identity_audience" {
  description = "Identity Application ID URI"
  value       = azuread_application.identity.client_id
}

# Optimize
output "optimize_client_id" {
  description = "Optimize Application (client) ID"
  value       = azuread_application.optimize.client_id
}

output "optimize_client_secret" {
  description = "Optimize Client Secret"
  value       = azuread_application_password.optimize.value
  sensitive   = true
}

output "optimize_audience" {
  description = "Optimize Application ID URI"
  value       = azuread_application.optimize.client_id
}

# Orchestration Cluster (Operate, Tasklist, Zeebe)
output "orchestration_client_id" {
  description = "Orchestration Cluster Application (client) ID"
  value       = azuread_application.orchestration.client_id
}

output "orchestration_client_secret" {
  description = "Orchestration Cluster Client Secret"
  value       = azuread_application_password.orchestration.value
  sensitive   = true
}

output "orchestration_audience" {
  description = "Orchestration Cluster Application ID URI"
  value       = azuread_application.orchestration.client_id
}

# Console (Single Page Application - no secret)
output "console_client_id" {
  description = "Console Application (client) ID"
  value       = azuread_application.console.client_id
}

output "console_audience" {
  description = "Console Application ID URI"
  value       = azuread_application.console.client_id
}

# WebModeler UI (Single Page Application - optional, no secret)
output "webmodeler_ui_client_id" {
  description = "WebModeler UI Application (client) ID"
  value       = var.enable_webmodeler ? azuread_application.webmodeler_ui[0].client_id : ""
}

output "webmodeler_ui_audience" {
  description = "WebModeler UI Application ID URI"
  value       = var.enable_webmodeler ? azuread_application.webmodeler_ui[0].client_id : ""
}

# WebModeler API (Web Application - optional)
output "webmodeler_api_client_id" {
  description = "WebModeler API Application (client) ID"
  value       = var.enable_webmodeler ? azuread_application.webmodeler_api[0].client_id : ""
}

output "webmodeler_api_client_secret" {
  description = "WebModeler API Client Secret"
  value       = var.enable_webmodeler ? azuread_application_password.webmodeler_api[0].value : ""
  sensitive   = true
}

output "webmodeler_api_audience" {
  description = "WebModeler API Application ID URI"
  value       = var.enable_webmodeler ? azuread_application.webmodeler_api[0].client_id : ""
}
