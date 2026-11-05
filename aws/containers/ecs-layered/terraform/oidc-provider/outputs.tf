locals {
  issuer_uri         = "${var.public_base_url}/auth/realms/${local.realm_name}"
  issuer_backend_uri = "http://${var.service_connect_name}:18080/auth/realms/${local.realm_name}"
  token_uri          = "${local.issuer_uri}/protocol/openid-connect/token"
}

output "issuer_uri" {
  value       = local.issuer_uri
  description = "OIDC issuer, as the browsers and the components see it"
}

output "clusters" {
  value = {
    for k, c in var.clusters : k => {
      issuer_uri                      = local.issuer_uri
      token_uri                       = local.token_uri
      orchestration_audience          = local.orchestration_audience
      orchestration_client_id         = "orchestration-${k}"
      orchestration_client_secret_arn = aws_secretsmanager_secret.orchestration_client[k].arn
      connectors_client_id            = "connectors-${k}"
      connectors_client_secret_arn    = aws_secretsmanager_secret.connectors_client[k].arn
      client_secrets_kms_key_arn      = var.secrets_kms_key_arn
    }
  }
  description = "Per Orchestration Cluster: the values of the identity layer's external_oidc, to pass to the identity layer of that cluster"
}

output "management" {
  value = {
    issuer_uri         = local.issuer_uri
    issuer_backend_uri = local.issuer_backend_uri
    username_claim     = "preferred_username"
    admin_claim        = var.admin_username
    identity = {
      client_id         = "camunda-identity"
      client_secret_arn = aws_secretsmanager_secret.identity_client.arn
      audience          = local.identity_audience
    }
    hub = {
      client_id         = "web-modeler"
      audience_internal = local.hub_audience_internal
      audience_public   = local.hub_audience_public
    }
  }
  description = "What Management Identity and Camunda Hub read: the issuer, the administrator claim, and their clients and audiences"
}

output "admin_user_password" {
  value       = random_password.realm_admin_user.result
  sensitive   = true
  description = "Password of the realm login user, who administers the platform. Also stored in Secrets Manager."
}

output "service_connect_name" {
  value       = var.service_connect_name
  description = "Name under which the components of the management plane reach the provider inside the ECS cluster"
}
