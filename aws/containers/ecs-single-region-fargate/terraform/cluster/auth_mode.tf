# Platform authentication mode.
#
#   basic     (default) - Orchestration Cluster and Connectors use built-in
#                         basic-auth users. The bundled Keycloak + Management
#                         Identity are still deployed (Identity needs an IdP), so
#                         the reference stays self-contained and can be flipped to
#                         "keycloak" without adding infrastructure.
#   keycloak            - Full OIDC against the bundled Keycloak `camunda-platform`
#                         realm that Management Identity bootstraps. Keycloak is
#                         exposed on the shared ALB for the browser login redirect.
#   external            - Bring-your-own OIDC provider (Entra ID, Okta, ...).
#                         Keycloak is NOT deployed; Orchestration, Connectors and
#                         Management Identity point at var.external_oidc instead.
#
# Everything that depends on "which IdP" is resolved once into the local.oidc_*
# values below, so the module blocks never branch on the provider themselves.

variable "authentication_mode" {
  type        = string
  description = "Platform authentication: 'basic' (built-in users, bundled Keycloak), 'keycloak' (OIDC via bundled Keycloak), or 'external' (bring-your-own OIDC, Keycloak skipped)."
  default     = "basic"

  validation {
    condition     = contains(["basic", "keycloak", "external"], var.authentication_mode)
    error_message = "authentication_mode must be one of: basic, keycloak, external."
  }
}

variable "external_oidc" {
  type = object({
    issuer_uri                      = string
    token_uri                       = string
    audience                        = string
    identity_client_id              = string
    identity_client_secret_arn      = string
    orchestration_client_id         = string
    orchestration_client_secret_arn = string
    connectors_client_id            = string
    connectors_client_secret_arn    = string
  })
  default     = null
  description = "External OIDC provider config, required only when authentication_mode = \"external\". One client per component (identity, orchestration, connectors); client secrets are passed as existing Secrets Manager ARNs (created out-of-band), never as raw values."
}

# Fail fast if external mode is selected without its config.
resource "terraform_data" "validate_authentication_mode" {
  lifecycle {
    precondition {
      condition     = var.authentication_mode != "external" || var.external_oidc != null
      error_message = "authentication_mode = \"external\" requires var.external_oidc (issuer_uri, token_uri, audience, client ids and client-secret ARNs)."
    }
  }
}

locals {
  oidc_enabled = var.authentication_mode != "basic"    # OIDC login used at all
  use_keycloak = var.authentication_mode != "external" # bundled Keycloak deployed
  is_external  = var.authentication_mode == "external"

  # Browser-facing base URL of the shared ALB. In keycloak mode it is also the
  # OIDC issuer host, so the token `iss` is identical for the browser and the
  # backend (which reaches the ALB via NAT egress). HTTP only in this demo.
  alb_base_url                = "http://${join("", aws_lb.main[*].dns_name)}"
  keycloak_public_base_url    = "${local.alb_base_url}/auth"
  camunda_realm_issuer_public = "${local.keycloak_public_base_url}/realms/camunda-platform"

  # Effective OIDC settings, resolved once: bundled Keycloak realm vs. external IdP.
  oidc_issuer_uri              = local.is_external ? try(var.external_oidc.issuer_uri, "") : local.camunda_realm_issuer_public
  oidc_token_uri               = local.is_external ? try(var.external_oidc.token_uri, "") : "${local.camunda_realm_issuer_public}/protocol/openid-connect/token"
  oidc_audience                = local.is_external ? try(var.external_oidc.audience, "") : "orchestration-api"
  oidc_redirect_uri            = "${local.alb_base_url}/sso-callback"
  oidc_orchestration_client_id = local.is_external ? try(var.external_oidc.orchestration_client_id, "") : "orchestration"
  oidc_connectors_client_id    = local.is_external ? try(var.external_oidc.connectors_client_id, "") : "connectors"

  # Client-secret ARNs consumed by the tasks: generated here for the bundled
  # Keycloak, or the customer-supplied ARNs for an external provider.
  oidc_orchestration_client_secret_arn = local.is_external ? try(var.external_oidc.orchestration_client_secret_arn, "") : (var.enable_orchestration_oidc_client ? aws_secretsmanager_secret.orchestration_oidc_client_secret[0].arn : "")
  oidc_connectors_client_secret_arn    = local.is_external ? try(var.external_oidc.connectors_client_secret_arn, "") : (var.enable_connectors_oidc_client ? aws_secretsmanager_secret.connectors_oidc_client_secret[0].arn : "")

  # Management Identity's own OIDC client (bundled: the generated camunda-identity
  # client; external: the customer-registered client).
  oidc_identity_client_id         = local.is_external ? try(var.external_oidc.identity_client_id, "") : "camunda-identity"
  oidc_identity_client_secret_arn = local.is_external ? try(var.external_oidc.identity_client_secret_arn, "") : (local.use_keycloak ? aws_secretsmanager_secret.identity_client_secret[0].arn : "")
}
