output "alb_endpoint" {
  value       = join("", aws_lb.main[*].dns_name)
  description = "(Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp."
}

output "nlb_endpoint" {
  value       = join("", aws_lb.grpc[*].dns_name)
  description = "(Optional) The DNS name of the Network Load Balancer (NLB) to access the Camunda Core."
}
output "admin_user_password" {
  value       = random_password.admin_user_password.result
  description = "The admin password for Camunda. Easy access purposes, saved in Secrets Manager."
  sensitive   = true
}

# --- OIDC (M2M) access for smoke tests / clients, populated in oidc mode ---
# Empty in basic mode. The client secret value is only available for the bundled
# Keycloak (external providers supply their own secret out-of-band).

output "oidc_token_url" {
  value       = local.oidc_enabled ? local.oidc.token_uri : ""
  description = "OIDC token endpoint for machine-to-machine authentication (empty in basic mode)."
}

output "connectors_oidc_client_id" {
  value       = local.oidc_enabled ? local.oidc.connectors.client_id : ""
  description = "OIDC client id used for machine-to-machine authentication (empty in basic mode)."
}

output "connectors_oidc_client_secret" {
  value       = try(random_password.connectors_oidc_client_secret[0].result, "")
  description = "OIDC client secret for the connectors client (bundled Keycloak only; empty otherwise)."
  sensitive   = true
}
