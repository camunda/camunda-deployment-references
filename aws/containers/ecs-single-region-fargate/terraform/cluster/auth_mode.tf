# Platform authentication mode toggle.
#
# - "basic" (default): the Orchestration Cluster and Connectors use built-in
#   basic-auth users; Keycloak/Identity are deployed but their realm OIDC clients
#   are provisioned-but-unused. This is the shipped reference default.
# - "oidc": the Orchestration Cluster and Connectors authenticate against the
#   Keycloak `camunda-platform` realm. Keycloak is exposed via the shared ALB so
#   the browser can complete the login redirect, and the OIDC issuer is the ALB
#   URL so the `iss` claim is identical for the browser and the backend.

variable "authentication_mode" {
  type        = string
  description = "Platform authentication mode: 'basic' (built-in users) or 'oidc' (Keycloak camunda-platform realm)."
  default     = "basic"

  validation {
    condition     = contains(["basic", "oidc"], var.authentication_mode)
    error_message = "authentication_mode must be either 'basic' or 'oidc'."
  }
}

locals {
  oidc_enabled = var.authentication_mode == "oidc"

  # Browser-facing base URL of the shared application load balancer. In oidc mode
  # this is both the browser entry point and the OIDC issuer host, so the token
  # `iss` claim is consistent for the browser and the orchestration backend (the
  # backend reaches the ALB via NAT egress). HTTP only in this demo.
  alb_base_url = "http://${join("", aws_lb.main[*].dns_name)}"

  # Public (browser + issuer) Keycloak URLs, used only in oidc mode.
  keycloak_public_base_url    = "${local.alb_base_url}/auth"
  camunda_realm_issuer_public = "${local.keycloak_public_base_url}/realms/camunda-platform"
}
