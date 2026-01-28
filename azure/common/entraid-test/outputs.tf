# Outputs for EntraID OIDC configuration

output "tenant_id" {
  description = "Azure AD Tenant ID"
  value       = data.azuread_client_config.current.tenant_id
}

output "client_id" {
  description = "Application (client) ID for all Camunda components (shared)"
  value       = azuread_application.camunda.client_id
}

output "application_id" {
  description = "Application object ID"
  value       = azuread_application.camunda.id
}

output "service_principal_id" {
  description = "Service Principal object ID"
  value       = azuread_service_principal.camunda.id
}

# OIDC Endpoints
output "issuer_url" {
  description = "OIDC Issuer URL (Azure AD authority)"
  value       = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
}

output "authorization_url" {
  description = "OIDC Authorization endpoint"
  value       = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/authorize"
}

output "token_url" {
  description = "OIDC Token endpoint"
  value       = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/token"
}

output "jwks_url" {
  description = "OIDC JWKS endpoint"
  value       = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/discovery/v2.0/keys"
}

output "userinfo_url" {
  description = "OIDC UserInfo endpoint"
  value       = "https://graph.microsoft.com/oidc/userinfo"
}

# Client Secrets (sensitive)
output "identity_client_secret" {
  description = "Client secret for Identity component"
  value       = azuread_application_password.identity.value
  sensitive   = true
}

output "optimize_client_secret" {
  description = "Client secret for Optimize component"
  value       = azuread_application_password.optimize.value
  sensitive   = true
}

output "orchestration_client_secret" {
  description = "Client secret for Orchestration"
  value       = azuread_application_password.orchestration.value
  sensitive   = true
}

output "connectors_client_secret" {
  description = "Client secret for Connectors"
  value       = azuread_application_password.connectors.value
  sensitive   = true
}

output "webmodeler_api_client_secret" {
  description = "Client secret for Web Modeler API"
  value       = var.enable_webmodeler ? azuread_application_password.webmodeler_api[0].value : ""
  sensitive   = true
}

# Test user
output "test_user_name" {
  description = "Username (UPN) of the test user for simulated login"
  value       = var.create_test_user ? azuread_user.test[0].user_principal_name : ""
}

output "test_user_password" {
  description = "Password of the test user"
  value       = var.create_test_user ? var.test_user_password : ""
  sensitive   = true
}

# Cleanup tracking
output "created_at" {
  description = "Timestamp when this EntraID app was created"
  value       = time_static.creation.rfc3339
}

output "expires_at" {
  description = "Timestamp when this EntraID app should be cleaned up"
  value       = null_resource.cleanup_marker.triggers.expires_at
}

# Combined output for convenience
output "oidc_config" {
  description = "Complete OIDC configuration for Camunda"
  value = {
    tenant_id         = data.azuread_client_config.current.tenant_id
    client_id         = azuread_application.camunda.client_id
    issuer_url        = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
    authorization_url = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/authorize"
    token_url         = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/token"
    jwks_url          = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/discovery/v2.0/keys"
    userinfo_url      = "https://graph.microsoft.com/oidc/userinfo"
  }
  sensitive = false
}
