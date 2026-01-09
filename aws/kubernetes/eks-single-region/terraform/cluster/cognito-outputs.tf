# Cognito Outputs for Camunda Components on AWS EKS

output "cognito_enabled" {
  description = "Whether Cognito authentication is enabled"
  value       = var.enable_cognito
}

# User Pool
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = var.enable_cognito ? aws_cognito_user_pool.camunda[0].id : ""
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = var.enable_cognito ? aws_cognito_user_pool.camunda[0].arn : ""
}

output "cognito_user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = var.enable_cognito ? aws_cognito_user_pool.camunda[0].endpoint : ""
}

output "cognito_domain" {
  description = "Cognito User Pool domain"
  value       = var.enable_cognito ? aws_cognito_user_pool_domain.camunda[0].domain : ""
}

# OIDC Endpoints (constructed from User Pool)
output "cognito_issuer_url" {
  description = "Cognito OIDC Issuer URL"
  value       = var.enable_cognito ? "https://cognito-idp.${var.enable_cognito ? data.aws_region.current.id : ""}.amazonaws.com/${aws_cognito_user_pool.camunda[0].id}" : ""
}

output "cognito_jwks_url" {
  description = "Cognito JWKS URL"
  value       = var.enable_cognito ? "https://cognito-idp.${var.enable_cognito ? data.aws_region.current.id : ""}.amazonaws.com/${aws_cognito_user_pool.camunda[0].id}/.well-known/jwks.json" : ""
}

output "cognito_token_url" {
  description = "Cognito Token URL"
  value       = var.enable_cognito ? "https://${aws_cognito_user_pool_domain.camunda[0].domain}.auth.${var.enable_cognito ? data.aws_region.current.id : ""}.amazoncognito.com/oauth2/token" : ""
}

output "cognito_authorization_url" {
  description = "Cognito Authorization URL"
  value       = var.enable_cognito ? "https://${aws_cognito_user_pool_domain.camunda[0].domain}.auth.${var.enable_cognito ? data.aws_region.current.id : ""}.amazoncognito.com/oauth2/authorize" : ""
}

# Identity Client
output "identity_client_id" {
  description = "Identity App Client ID"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.identity[0].id : ""
}

output "identity_client_secret" {
  description = "Identity App Client Secret"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.identity[0].client_secret : ""
  sensitive   = true
}

# Optimize Client
output "optimize_client_id" {
  description = "Optimize App Client ID"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.optimize[0].id : ""
}

output "optimize_client_secret" {
  description = "Optimize App Client Secret"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.optimize[0].client_secret : ""
  sensitive   = true
}

# Orchestration Client
output "orchestration_client_id" {
  description = "Orchestration App Client ID"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.orchestration[0].id : ""
}

output "orchestration_client_secret" {
  description = "Orchestration App Client Secret"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.orchestration[0].client_secret : ""
  sensitive   = true
}

# Console Client (no secret - SPA)
output "console_client_id" {
  description = "Console App Client ID"
  value       = var.enable_cognito && var.enable_console ? aws_cognito_user_pool_client.console[0].id : ""
}

# Connectors Client
output "connectors_client_id" {
  description = "Connectors App Client ID"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.connectors[0].id : ""
}

output "connectors_client_secret" {
  description = "Connectors App Client Secret"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.connectors[0].client_secret : ""
  sensitive   = true
}

# WebModeler UI Client (no secret - SPA)
output "webmodeler_ui_client_id" {
  description = "WebModeler UI App Client ID"
  value       = var.enable_cognito && var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_ui[0].id : ""
}

# WebModeler API Client
output "webmodeler_api_client_id" {
  description = "WebModeler API App Client ID"
  value       = var.enable_cognito && var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_api[0].id : ""
}

output "webmodeler_api_client_secret" {
  description = "WebModeler API App Client Secret"
  value       = var.enable_cognito && var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_api[0].client_secret : ""
  sensitive   = true
}

# Domain name
output "camunda_domain_name" {
  description = "Domain name for Camunda deployment"
  value       = var.domain_name
}

output "identity_initial_user_email" {
  description = "Email of the initial admin user"
  value       = var.identity_initial_user_email
}

# Data source for current region
data "aws_region" "current" {}
