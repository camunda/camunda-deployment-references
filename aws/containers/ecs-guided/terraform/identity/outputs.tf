output "oidc" {
  value       = local.oidc
  description = "Identity contract. null in basic mode, otherwise the OIDC settings every component reads: issuer_uri, token_uri, audience, redirect_uri, claim names, and one client (id and secret ARN) per component."
}

output "authentication_mode" {
  value       = var.authentication_mode
  description = "basic or oidc"
}
