# Platform authentication mode.
#
#   basic (default) - Orchestration Cluster and Connectors use built-in basic-auth
#                     users. No OIDC provider is deployed: neither the bundled
#                     Keycloak nor Management Identity. Fully self-contained.
#   oidc            - OIDC authentication across the platform. The identity provider
#                     is selected automatically from var.external_oidc:
#                       * external_oidc == null (default) -> a self-contained bundled
#                         Keycloak is deployed and self-provisions the
#                         `camunda-platform` realm (Keycloak --import-realm), so the
#                         reference runs out of the box with no external dependency.
#                       * external_oidc != null -> the customer's OIDC provider
#                         (Entra ID, Okta, ...) is used and Keycloak is NOT deployed.
#
# Either way every component consumes the single provider-agnostic `local.oidc`
# object below and never references Keycloak: the bundled Keycloak is just the
# default OIDC provider we ship, wired exactly like an external one.

variable "authentication_mode" {
  type        = string
  description = "Platform authentication: 'basic' (built-in users, no IdP deployed) or 'oidc' (OIDC via the bundled Keycloak by default, or an external provider when var.external_oidc is set)."
  default     = "basic"

  validation {
    condition     = contains(["basic", "oidc"], var.authentication_mode)
    error_message = "authentication_mode must be one of: basic, oidc."
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
  description = "External OIDC provider config. Optional and only honored when authentication_mode = \"oidc\": when set, that provider is used and the bundled Keycloak is skipped; when null (default), a bundled Keycloak is deployed as the OIDC provider. One client per component (identity, orchestration, connectors); client secrets are existing Secrets Manager ARNs (created out-of-band), never raw values."
}

# Fail fast if external_oidc is supplied while OIDC is not enabled.
resource "terraform_data" "validate_authentication_mode" {
  lifecycle {
    precondition {
      condition     = var.external_oidc == null || var.authentication_mode == "oidc"
      error_message = "var.external_oidc is only valid when authentication_mode = \"oidc\" (in basic mode no OIDC provider is deployed)."
    }
    # When an external provider is supplied, every field must be non-empty: these
    # values flow straight into task env vars / secret ARNs, so an empty string
    # would plan cleanly but fail confusingly at runtime.
    precondition {
      condition = var.external_oidc == null || alltrue([
        for v in [
          var.external_oidc.issuer_uri,
          var.external_oidc.token_uri,
          var.external_oidc.audience,
          var.external_oidc.identity_client_id,
          var.external_oidc.identity_client_secret_arn,
          var.external_oidc.orchestration_client_id,
          var.external_oidc.orchestration_client_secret_arn,
          var.external_oidc.connectors_client_id,
          var.external_oidc.connectors_client_secret_arn,
        ] : trimspace(v) != ""
      ])
      error_message = "When var.external_oidc is set, all of its fields (issuer_uri, token_uri, audience, and each component's client_id and client_secret_arn) must be non-empty."
    }
    # The authorization seed lands on the Management Identity task, which only exists in
    # oidc mode. Silently ignoring the flag in basic mode would look like a broken seed.
    precondition {
      condition     = !var.enable_web_modeler_authorization || var.authentication_mode == "oidc"
      error_message = "var.enable_web_modeler_authorization requires authentication_mode = \"oidc\" (Management Identity is not deployed in basic mode)."
    }
  }
}

locals {
  oidc_enabled            = var.authentication_mode == "oidc"               # OIDC used at all
  use_external            = local.oidc_enabled && var.external_oidc != null # bring-your-own IdP
  deploy_bundled_keycloak = local.oidc_enabled && var.external_oidc == null # ship the default IdP

  # Browser-facing base URL of the shared ALB. For the bundled Keycloak it is also the
  # OIDC issuer host, so the token `iss` is identical for the browser and the backend
  # (which reaches the ALB via NAT egress). HTTP only in this demo.
  alb_base_url                = "http://${join("", aws_lb.main[*].dns_name)}"
  keycloak_public_base_url    = "${local.alb_base_url}/auth"
  camunda_realm_issuer_public = "${local.keycloak_public_base_url}/realms/camunda-platform"

  # Management Identity's own base URL on the shared ALB (used both for its
  # CAMUNDA_IDENTITY_BASE_URL and for the camunda-identity client redirect in the
  # bundled realm import).
  identity_public_base = "${local.alb_base_url}/identity"

  # Single provider-agnostic OIDC interface. Every component reads only this object;
  # it is populated identically whether the IdP is the bundled Keycloak or external.
  oidc = {
    issuer_uri   = local.use_external ? try(var.external_oidc.issuer_uri, "") : local.camunda_realm_issuer_public
    token_uri    = local.use_external ? try(var.external_oidc.token_uri, "") : "${local.camunda_realm_issuer_public}/protocol/openid-connect/token"
    audience     = local.use_external ? try(var.external_oidc.audience, "") : "orchestration-api"
    redirect_uri = "${local.alb_base_url}/sso-callback"

    orchestration = {
      client_id         = local.use_external ? try(var.external_oidc.orchestration_client_id, "") : "orchestration"
      client_secret_arn = local.use_external ? try(var.external_oidc.orchestration_client_secret_arn, "") : try(aws_secretsmanager_secret.orchestration_oidc_client_secret[0].arn, "")
    }

    connectors = {
      client_id         = local.use_external ? try(var.external_oidc.connectors_client_id, "") : "connectors"
      client_secret_arn = local.use_external ? try(var.external_oidc.connectors_client_secret_arn, "") : try(aws_secretsmanager_secret.connectors_oidc_client_secret[0].arn, "")
    }

    identity = {
      client_id         = local.use_external ? try(var.external_oidc.identity_client_id, "") : "camunda-identity"
      client_secret_arn = local.use_external ? try(var.external_oidc.identity_client_secret_arn, "") : try(aws_secretsmanager_secret.identity_client_secret[0].arn, "")
      # Management Identity's own resource-server audience (mandatory in generic OIDC).
      audience = local.use_external ? try(var.external_oidc.audience, "") : "camunda-identity-resource-server"
    }
  }
}
