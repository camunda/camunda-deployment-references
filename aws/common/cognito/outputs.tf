# Outputs for AWS Cognito OIDC configuration

# User Pool info
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.camunda.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.camunda.arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = aws_cognito_user_pool.camunda.endpoint
}

output "cognito_domain" {
  description = "Cognito User Pool domain prefix"
  value       = aws_cognito_user_pool_domain.camunda.domain
}

# OIDC Endpoints
output "issuer_url" {
  description = "OIDC Issuer URL"
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.camunda.id}"
}

output "authorization_url" {
  description = "OIDC Authorization endpoint"
  value       = "https://${aws_cognito_user_pool_domain.camunda.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/authorize"
}

output "token_url" {
  description = "OIDC Token endpoint"
  value       = "https://${aws_cognito_user_pool_domain.camunda.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/token"
}

output "jwks_url" {
  description = "OIDC JWKS endpoint"
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.camunda.id}/.well-known/jwks.json"
}

output "userinfo_url" {
  description = "OIDC UserInfo endpoint"
  value       = "https://${aws_cognito_user_pool_domain.camunda.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/userInfo"
}

output "logout_url" {
  description = "Logout endpoint"
  value       = "https://${aws_cognito_user_pool_domain.camunda.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/logout"
}

# Resource Server
output "resource_server_identifier" {
  description = "Resource Server identifier (used as scope prefix)"
  value       = aws_cognito_resource_server.camunda.identifier
}

# Client IDs
output "identity_client_id" {
  description = "Identity App Client ID"
  value       = aws_cognito_user_pool_client.identity.id
}

output "optimize_client_id" {
  description = "Optimize App Client ID"
  value       = aws_cognito_user_pool_client.optimize.id
}

output "orchestration_client_id" {
  description = "Orchestration App Client ID"
  value       = aws_cognito_user_pool_client.orchestration.id
}

output "console_client_id" {
  description = "Console App Client ID (empty if not enabled)"
  value       = var.enable_console ? aws_cognito_user_pool_client.console[0].id : ""
}

output "connectors_client_id" {
  description = "Connectors App Client ID"
  value       = aws_cognito_user_pool_client.connectors.id
}

output "webmodeler_ui_client_id" {
  description = "WebModeler UI App Client ID (empty if not enabled)"
  value       = var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_ui[0].id : ""
}

output "webmodeler_api_client_id" {
  description = "WebModeler API App Client ID (empty if not enabled)"
  value       = var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_api[0].id : ""
}

# Client Secrets (sensitive)
output "identity_client_secret" {
  description = "Identity App Client Secret"
  value       = aws_cognito_user_pool_client.identity.client_secret
  sensitive   = true
}

output "optimize_client_secret" {
  description = "Optimize App Client Secret"
  value       = aws_cognito_user_pool_client.optimize.client_secret
  sensitive   = true
}

output "orchestration_client_secret" {
  description = "Orchestration App Client Secret"
  value       = aws_cognito_user_pool_client.orchestration.client_secret
  sensitive   = true
}

output "connectors_client_secret" {
  description = "Connectors App Client Secret"
  value       = aws_cognito_user_pool_client.connectors.client_secret
  sensitive   = true
}

output "webmodeler_api_client_secret" {
  description = "WebModeler API App Client Secret (empty if not enabled)"
  value       = var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_api[0].client_secret : ""
  sensitive   = true
}

# Test user
output "test_user_name" {
  description = "Username (email) of the test user"
  value       = var.create_test_user ? aws_cognito_user.test[0].username : ""
}

output "test_user_password" {
  description = "Password of the test user"
  value       = var.create_test_user ? var.test_user_password : ""
  sensitive   = true
}

# Cleanup tracking
output "created_at" {
  description = "Timestamp when this Cognito pool was created"
  value       = time_static.creation.rfc3339
}

output "expires_at" {
  description = "Timestamp when this Cognito pool should be cleaned up"
  value       = null_resource.cleanup_marker.triggers.expires_at
}

# AWS Region info
output "aws_region" {
  description = "AWS Region where Cognito is deployed"
  value       = data.aws_region.current.name
}

# Combined output for convenience
output "oidc_config" {
  description = "Complete OIDC configuration for Camunda"
  value = {
    user_pool_id      = aws_cognito_user_pool.camunda.id
    issuer_url        = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.camunda.id}"
    authorization_url = "https://${aws_cognito_user_pool_domain.camunda.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/authorize"
    token_url         = "https://${aws_cognito_user_pool_domain.camunda.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/token"
    jwks_url          = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.camunda.id}/.well-known/jwks.json"
    userinfo_url      = "https://${aws_cognito_user_pool_domain.camunda.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/userInfo"
  }
  sensitive = false
}
