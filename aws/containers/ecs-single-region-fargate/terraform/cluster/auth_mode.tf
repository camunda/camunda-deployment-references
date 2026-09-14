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
    issuer_uri = string
    token_uri  = string

    # One audience per resource server. The Orchestration Cluster and Management
    # Identity are two distinct APIs: orchestration validates its own audience, while
    # Identity keys its resource-server declarations and every role permission on
    # its own. Collapsing them onto one value points Identity's permissions at the
    # orchestration API, so they are separate inputs.
    orchestration_audience = string
    identity_audience      = string

    identity_client_id              = string
    identity_client_secret_arn      = string
    orchestration_client_id         = string
    orchestration_client_secret_arn = string
    connectors_client_id            = string
    connectors_client_secret_arn    = string

    # Token claim names. The defaults are what Keycloak emits; other providers differ,
    # so they are overridable. Entra ID in particular does not emit `client_id` and
    # identifies the calling application with `azp` (v2) or `appid` (v1).
    username_claim  = optional(string, "preferred_username")
    client_id_claim = optional(string, "client_id")

    # Scope requested by Connectors on the client-credentials token request. Keycloak
    # needs none, so this is empty by default and the env var is only set when given.
    # Entra ID v2 rejects a client-credentials request without `<resource>/.default`.
    connectors_token_scope = optional(string, "")
  })
  default     = null
  description = "External OIDC provider config. Optional and only honored when authentication_mode = \"oidc\": when set, that provider is used and the bundled Keycloak is skipped; when null (default), a bundled Keycloak is deployed as the OIDC provider. One client per component (identity, orchestration, connectors) and one audience per resource server (orchestration, identity); client secrets are existing Secrets Manager ARNs (created out-of-band), never raw values. The client secrets must be decryptable by the ECS task role, whose kms:Decrypt statement is scoped to a single key: encrypt them either with the AWS-managed Secrets Manager key, or with the same customer-managed key this stack uses (var.secrets_kms_key_arn, which replaces the CMK the stack would otherwise create). A secret under any other CMK is readable but not decryptable and fails at task start with ResourceInitializationError."
}

variable "alb_public_hostname" {
  type        = string
  description = "Public DNS name clients use to reach the shared ALB (for example camunda.example.com, an alias record pointing at the ALB). Required when var.alb_certificate_arn is set, because every OIDC URL (issuer, redirect URI, Management Identity base URL) is built from it and no ACM certificate can cover the ALB's own *.elb.amazonaws.com name. Empty (default) falls back to the ALB's own DNS name, which is correct for the plain-HTTP demo."
  default     = ""
}

variable "admin_claim_value" {
  type        = string
  description = "Value of the username claim that identifies the platform administrator. Grants the Orchestration Cluster admin role and, when var.enable_web_modeler_authorization is set, the Management Identity roles. Defaults to \"admin\", which is the user the bundled Keycloak realm creates; with an external provider set this to a principal that exists in your directory, otherwise nobody is granted admin."
  default     = "admin"

  validation {
    condition     = trimspace(var.admin_claim_value) != ""
    error_message = "admin_claim_value must not be empty: it is the claim value that grants the admin role."
  }
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
          var.external_oidc.orchestration_audience,
          var.external_oidc.identity_audience,
          var.external_oidc.identity_client_id,
          var.external_oidc.identity_client_secret_arn,
          var.external_oidc.orchestration_client_id,
          var.external_oidc.orchestration_client_secret_arn,
          var.external_oidc.connectors_client_id,
          var.external_oidc.connectors_client_secret_arn,
        ] : trimspace(v) != ""
      ])
      error_message = "When var.external_oidc is set, all of its required fields (issuer_uri, token_uri, orchestration_audience, identity_audience, and each component's client_id and client_secret_arn) must be non-empty."
    }
    # TLS on the ALB's own DNS name cannot work: ACM will not issue a certificate for
    # *.elb.amazonaws.com, so both the browser and the backends would reject the
    # connection on hostname verification. Catch it at plan time instead of at login.
    precondition {
      condition     = var.alb_certificate_arn == "" || trimspace(var.alb_public_hostname) != ""
      error_message = "var.alb_public_hostname must be set when var.alb_certificate_arn is set: the OIDC issuer and redirect URIs are built from it, and no ACM certificate can cover the ALB's own *.elb.amazonaws.com name."
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
  # (which reaches the ALB via NAT egress).
  #
  # The scheme must follow the listener. With a certificate the ALB redirects :80 to
  # :443 and Keycloak, running with KC_PROXY_HEADERS=xforwarded, derives its frontend
  # URL from X-Forwarded-Proto and therefore publishes an `https` issuer. Pinning this
  # to `http` would leave every component validating an issuer the provider never
  # emits, and the OIDC flow would fail on an issuer mismatch rather than anything
  # that points at the scheme.
  # The hostname must be one the certificate can actually cover. ACM does not issue for
  # the ALB's own *.elb.amazonaws.com name, so serving TLS on the raw ALB DNS name fails
  # hostname verification for the browser and for the backends that fetch the discovery
  # document and the token. var.alb_public_hostname supplies the real name; without TLS
  # the ALB's own name is correct and needs no certificate.
  alb_scheme                  = local.alb_https_enabled ? "https" : "http"
  alb_hostname                = var.alb_public_hostname != "" ? var.alb_public_hostname : join("", aws_lb.main[*].dns_name)
  alb_base_url                = "${local.alb_scheme}://${local.alb_hostname}"
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
    audience     = local.use_external ? try(var.external_oidc.orchestration_audience, "") : "orchestration-api"
    redirect_uri = "${local.alb_base_url}/sso-callback"

    # Claim names the Orchestration Cluster reads. The bundled realm emits both (the
    # client_id one via an explicit protocol mapper in keycloak_realm.tf).
    username_claim  = local.use_external ? try(var.external_oidc.username_claim, "preferred_username") : "preferred_username"
    client_id_claim = local.use_external ? try(var.external_oidc.client_id_claim, "client_id") : "client_id"

    orchestration = {
      client_id         = local.use_external ? try(var.external_oidc.orchestration_client_id, "") : "orchestration"
      client_secret_arn = local.use_external ? try(var.external_oidc.orchestration_client_secret_arn, "") : try(aws_secretsmanager_secret.orchestration_oidc_client_secret[0].arn, "")
    }

    connectors = {
      client_id         = local.use_external ? try(var.external_oidc.connectors_client_id, "") : "connectors"
      client_secret_arn = local.use_external ? try(var.external_oidc.connectors_client_secret_arn, "") : try(aws_secretsmanager_secret.connectors_oidc_client_secret[0].arn, "")
      # Empty for the bundled realm, which issues client-credentials tokens without a
      # scope; only emitted as an env var when a provider requires one.
      token_scope = local.use_external ? try(var.external_oidc.connectors_token_scope, "") : ""
    }

    identity = {
      client_id         = local.use_external ? try(var.external_oidc.identity_client_id, "") : "camunda-identity"
      client_secret_arn = local.use_external ? try(var.external_oidc.identity_client_secret_arn, "") : try(aws_secretsmanager_secret.identity_client_secret[0].arn, "")
      # Management Identity's own resource-server audience (mandatory in generic OIDC).
      audience = local.use_external ? try(var.external_oidc.identity_audience, "") : "camunda-identity-resource-server"
    }
  }
}
