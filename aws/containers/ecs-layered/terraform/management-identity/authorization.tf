# The authorization model of Management Identity: component presets (resource servers,
# permissions, roles) and a mapping rule that grants the roles to the administrator.
#
# Management Identity ships no roles. In the generic OIDC profile it cannot read role
# assignments out of the provider, so a role is granted by matching a token claim.

locals {
  hub_authorization_enabled = var.enable_hub_authorization

  admin_claim_name  = var.oidc.username_claim
  admin_claim_value = var.oidc.admin_claim

  # Management Identity's own resource server. Both Web Modeler roles carry a read:users
  # permission on it, so it is declared even if only Camunda Hub is in play.
  preset_identity = {
    apis = [
      {
        name     = "Camunda Identity Resource Server"
        audience = var.oidc.identity.audience
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
          { audience = var.oidc.identity.audience, definition = "read" },
          { audience = var.oidc.identity.audience, definition = "write" },
        ]
      },
    ]
  }

  # Camunda Hub: the APIs and roles that Web Modeler asks about.
  preset_hub = {
    apis = [
      {
        name     = "Web Modeler Internal API"
        audience = var.oidc.hub.audience_internal
        permissions = [
          { definition = "write:*", description = "Write permission" },
          { definition = "admin:*", description = "Admin permission" },
        ]
      },
      {
        name     = "Web Modeler API"
        audience = var.oidc.hub.audience_public
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
          { audience = var.oidc.hub.audience_internal, definition = "write:*" },
          { audience = var.oidc.identity.audience, definition = "read:users" },
        ]
      },
      {
        name        = "Web Modeler Admin"
        description = "Grants elevated access to Web Modeler"
        permissions = [
          { audience = var.oidc.identity.audience, definition = "read:users" },
          { audience = var.oidc.hub.audience_internal, definition = "write:*" },
          { audience = var.oidc.hub.audience_internal, definition = "admin:*" },
        ]
      },
    ]
  }

  admin_role_names = distinct(flatten([
    for preset in [local.preset_identity, local.preset_hub] : [for role in preset.roles : role.name]
  ]))

  # The bootstrap pair creates a default rule for the first administrator. It is exclusive with the
  # declared mapping rule below (Identity de-duplicates rules on claim name, value, and type), so it
  # is dropped when the model is declared.
  bootstrap_env = local.hub_authorization_enabled ? [] : [
    { name = "IDENTITY_INITIAL_CLAIM_NAME", value = local.admin_claim_name },
    { name = "IDENTITY_INITIAL_CLAIM_VALUE", value = local.admin_claim_value },
  ]

  # Nested lists cannot be expressed as environment variables: the model is one JSON value.
  authorization_env = local.hub_authorization_enabled ? [
    { name = "SPRING_APPLICATION_JSON", value = local.authorization_json },
  ] : []

  authorization_json = jsonencode({
    identity = {
      "component-presets" = {
        identity   = local.preset_identity
        webmodeler = local.preset_hub
      }
      "mapping-rules" = [
        {
          name                 = "Camunda Admin"
          "claim-name"         = local.admin_claim_name
          "claim-value"        = local.admin_claim_value
          operator             = "EQUALS"
          "rule-type"          = "ROLE"
          "applied-role-names" = local.admin_role_names
        },
      ]
    }
  })
}
