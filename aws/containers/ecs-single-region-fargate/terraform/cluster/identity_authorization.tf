# Management Identity authorization model (component presets + mapping rules).
#
# Authorization in Camunda 8 is split across two components:
#
#   * The Orchestration Cluster (Zeebe / Operate / Tasklist / v2 API) owns its own
#     authorization and is seeded Camunda-side via CAMUNDA_SECURITY_INITIALIZATION_*
#     (see camunda.tf).
#   * Web Modeler / Camunda Hub, Console and Optimize resolve permissions through
#     Management Identity's RBAC model instead: a role is a named set of
#     (audience, definition) permissions, and a principal is granted roles.
#
# Management Identity ships no roles out of the box — they are declared by
# `identity.component-presets`. In the generic OIDC profile Identity does not manage
# the IdP, so the Keycloak-only path for granting them (`keycloak.users[].roles`) is
# unavailable; roles are granted by matching a token claim through
# `identity.mapping-rules`. Both keys are honored in the `oidc` profile — the upstream
# Helm chart renders them outside its `authIssuerType == "KEYCLOAK"` guard.
#
# The preset and role definitions below are copied from the reference Helm chart
# (camunda-platform-helm, charts/camunda-platform-8.10/templates/identity/configmap.yaml)
# so this reference architecture stays in lockstep with it.

variable "enable_web_modeler_authorization" {
  type        = bool
  default     = false
  description = "Seed Management Identity with the Web Modeler authorization model: the component presets declaring the Web Modeler resource servers, permissions and roles, plus a mapping rule granting them to the admin principal. Requires authentication_mode = \"oidc\". Enable this when a Web Modeler / Camunda Hub deployment consumes this Identity, otherwise Web Modeler authenticates but every authorization check is denied."
}

locals {
  webmodeler_authorization_enabled = local.oidc_enabled && var.enable_web_modeler_authorization

  # Web Modeler resource-server audiences. App-contract identifiers (the Helm chart's
  # webModeler.clientApiAudience / publicApiAudience defaults), so they are fixed here.
  webmodeler_audience_internal = "web-modeler-api"
  webmodeler_audience_public   = "web-modeler-public-api"

  # The principal that receives the roles below. Shared with the IDENTITY_INITIAL_CLAIM_*
  # env vars in camunda.tf so the claim that bootstraps the first admin and the claim the
  # mapping rule matches on cannot drift apart.
  identity_admin_claim_name  = "preferred_username"
  identity_admin_claim_value = "admin"

  # Management Identity's own resource server. Required even when only Web Modeler is in
  # play: both Web Modeler roles carry a `read:users` permission on this audience, so it
  # must be declared for those roles to resolve.
  identity_preset_identity = {
    apis = [
      {
        name     = "Camunda Identity Resource Server"
        audience = local.oidc.identity.audience
        permissions = [
          { definition = "read", description = "Read permission" },
          { definition = "read:users", description = "Read users permission" },
          { definition = "write", description = "Write permission" },
        ]
      },
    ]
    roles = [
      {
        name        = "ManagementIdentity"
        description = "Provides full access to Management Identity"
        permissions = [
          { audience = local.oidc.identity.audience, definition = "read" },
          { audience = local.oidc.identity.audience, definition = "write" },
        ]
      },
    ]
  }

  # Web Modeler / Camunda Hub. `applications` entries are intentionally omitted: in the
  # generic OIDC profile the IdP owns the clients (the bundled realm import creates the
  # `web-modeler` client), and Identity is only a resource server here.
  identity_preset_webmodeler = {
    apis = [
      {
        name     = "Web Modeler Internal API"
        audience = local.webmodeler_audience_internal
        permissions = [
          { definition = "write:*", description = "Write permission" },
          { definition = "admin:*", description = "Admin permission" },
        ]
      },
      {
        name     = "Web Modeler API"
        audience = local.webmodeler_audience_public
        permissions = [
          { definition = "create:*", description = "Allows create access for all resources" },
          { definition = "read:*", description = "Allows read access to all resources" },
          { definition = "update:*", description = "Allows update access to all resources" },
          { definition = "delete:*", description = "Allows delete access for all resources" },
        ]
      },
    ]
    roles = [
      {
        name        = "Web Modeler"
        description = "Grants full access to Web Modeler"
        permissions = [
          { audience = local.webmodeler_audience_internal, definition = "write:*" },
          { audience = local.oidc.identity.audience, definition = "read:users" },
        ]
      },
      {
        name        = "Web Modeler Admin"
        description = "Grants elevated access to Web Modeler"
        permissions = [
          { audience = local.oidc.identity.audience, definition = "read:users" },
          { audience = local.webmodeler_audience_internal, definition = "write:*" },
          { audience = local.webmodeler_audience_internal, definition = "admin:*" },
        ]
      },
    ]
  }

  # Grant every role declared above to the admin principal. In the generic OIDC profile
  # this is the only way to bind a role to a user: Identity cannot read role assignments
  # out of the IdP, so it matches an incoming token claim instead.
  identity_admin_role_names = distinct(flatten([
    for _, preset in [local.identity_preset_identity, local.identity_preset_webmodeler] :
    [for role in preset.roles : role.name]
  ]))

  # Nested maps and lists cannot be expressed as relaxed-binding environment variables,
  # so the whole block is handed to the task as a single SPRING_APPLICATION_JSON value.
  # It sets only identity.component-presets and identity.mapping-rules; the scalar
  # IDENTITY_* and CAMUNDA_IDENTITY_* env vars bind independently.
  identity_authorization_json = jsonencode({
    identity = {
      "component-presets" = {
        identity   = local.identity_preset_identity
        webmodeler = local.identity_preset_webmodeler
      }
      "mapping-rules" = [
        {
          name                 = "Camunda Admin"
          "claim-name"         = local.identity_admin_claim_name
          "claim-value"        = local.identity_admin_claim_value
          operator             = "EQUALS"
          "rule-type"          = "ROLE"
          "applied-role-names" = local.identity_admin_role_names
        },
      ]
    }
  })
}
