# Builds the Management Identity realm-bootstrap config (mirrors Camunda's
# .identity/application.yaml) and renders it as SPRING_APPLICATION_JSON.
# Component presets are opt-in via the enable_*_oidc_client flags. Secret values
# are ${...} placeholders resolved at runtime from the ECS-injected env vars.

locals {
  keycloak_internal_url = "http://keycloak:18080/auth"
  camunda_realm_issuer  = "${local.keycloak_internal_url}/realms/camunda-platform"

  identity_preset_identity = {
    apis = [{
      name     = "Camunda Identity Resource Server"
      audience = "camunda-identity-resource-server"
      permissions = [
        { definition = "read", description = "Read permission" },
        { definition = "read:users", description = "Read users permission" },
        { definition = "write", description = "Write permission" },
      ]
    }]
    roles = [{
      name        = "ManagementIdentity"
      description = "Provides full access to Identity"
      permissions = [
        { audience = "camunda-identity-resource-server", definition = "read" },
        { audience = "camunda-identity-resource-server", definition = "write" },
      ]
    }]
  }

  identity_preset_orchestration = {
    applications = [{
      name            = "Orchestration"
      id              = "orchestration"
      type            = "confidential"
      secret          = "$${VALUES_KEYCLOAK_INIT_ORCHESTRATION_SECRET}"
      "root-url"      = "http://localhost:8080"
      "redirect-uris" = ["/sso-callback"]
    }]
    apis = [{
      name     = "Orchestration API"
      audience = "orchestration-api"
      permissions = [
        { definition = "read:*", description = "Read permission" },
        { definition = "write:*", description = "Write permission" },
      ]
    }]
    roles = [{
      name        = "Orchestration"
      description = "Grants full access to Orchestration"
      permissions = [
        { audience = "orchestration-api", definition = "read:*" },
        { audience = "orchestration-api", definition = "write:*" },
      ]
    }]
  }

  identity_preset_connectors = {
    applications = [{
      name   = "Connectors"
      id     = "connectors"
      type   = "m2m"
      secret = "$${VALUES_KEYCLOAK_INIT_CONNECTORS_SECRET}"
      permissions = [
        { audience = "orchestration-api", definition = "read:*" },
      ]
    }]
  }

  identity_preset_optimize = {
    applications = [{
      name            = "Optimize"
      id              = "optimize"
      type            = "confidential"
      secret          = "$${VALUES_KEYCLOAK_INIT_OPTIMIZE_SECRET}"
      "root-url"      = "http://localhost:8083"
      "redirect-uris" = ["/api/authentication/callback"]
      permissions = [
        { audience = "optimize-api", definition = "write:*" },
      ]
    }]
    apis = [{
      name     = "Optimize API"
      audience = "optimize-api"
      permissions = [
        { definition = "write:*", description = "Write permission" },
      ]
    }]
    roles = [{
      name        = "Optimize"
      description = "Grants full access to Optimize"
      permissions = [
        { audience = "optimize-api", definition = "write:*" },
        { audience = "camunda-identity-resource-server", definition = "read:users" },
      ]
    }]
  }

  identity_preset_console = {
    applications = [{
      name            = "Console"
      id              = "console"
      type            = "public"
      "root-url"      = "http://localhost:8087"
      "redirect-uris" = ["/"]
    }]
    apis = [{
      name     = "Console API"
      audience = "console-api"
      permissions = [
        { definition = "write:*", description = "Write permission" },
      ]
    }]
    roles = [{
      name        = "Console"
      description = "Grants full access to Console"
      permissions = [
        { audience = "console-api", definition = "write:*" },
      ]
    }]
  }

  identity_preset_webmodeler = {
    applications = [{
      name            = "Web Modeler"
      id              = "web-modeler"
      type            = "public"
      "root-url"      = "http://localhost:8070"
      "redirect-uris" = ["/login-callback"]
    }]
    apis = [
      {
        name     = "Web Modeler Internal API"
        audience = "web-modeler-api"
        permissions = [
          { definition = "write:*", description = "Write permission" },
          { definition = "admin:*", description = "Admin permission" },
        ]
      },
      {
        name     = "Web Modeler API"
        audience = "web-modeler-public-api"
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
          { audience = "web-modeler-api", definition = "write:*" },
          { audience = "camunda-identity-resource-server", definition = "read:users" },
        ]
      },
      {
        name        = "Web Modeler Admin"
        description = "Grants elevated access to Web Modeler"
        permissions = [
          { audience = "camunda-identity-resource-server", definition = "read:users" },
          { audience = "web-modeler-api", definition = "write:*" },
          { audience = "web-modeler-api", definition = "admin:*" },
        ]
      },
    ]
  }

  identity_component_presets = merge(
    { identity = local.identity_preset_identity },
    var.enable_orchestration_oidc_client ? { orchestration = local.identity_preset_orchestration } : {},
    var.enable_connectors_oidc_client ? { connectors = local.identity_preset_connectors } : {},
    var.enable_optimize_oidc_client ? { optimize = local.identity_preset_optimize } : {},
    var.enable_console_oidc_client ? { console = local.identity_preset_console } : {},
    var.enable_web_modeler_oidc_client ? { webmodeler = local.identity_preset_webmodeler } : {},
  )

  keycloak_init = merge(
    var.enable_orchestration_oidc_client ? { orchestration = { secret = "$${VALUES_KEYCLOAK_INIT_ORCHESTRATION_SECRET}" } } : {},
    var.enable_connectors_oidc_client ? { connectors = { secret = "$${VALUES_KEYCLOAK_INIT_CONNECTORS_SECRET}" } } : {},
    var.enable_optimize_oidc_client ? { optimize = { secret = "$${VALUES_KEYCLOAK_INIT_OPTIMIZE_SECRET}" } } : {},
    var.enable_console_oidc_client ? { console = { secret = "$${VALUES_KEYCLOAK_INIT_CONSOLE_SECRET}" } } : {},
    var.enable_web_modeler_oidc_client ? { webmodeler = { "root-url" = "http://localhost:8070" } } : {},
  )

  demo_user_roles = concat(
    ["ManagementIdentity"],
    var.enable_orchestration_oidc_client ? ["Orchestration"] : [],
    var.enable_optimize_oidc_client ? ["Optimize"] : [],
    var.enable_console_oidc_client ? ["Console"] : [],
    var.enable_web_modeler_oidc_client ? ["Web Modeler", "Web Modeler Admin"] : [],
  )

  identity_realm_config = {
    identity = {
      url   = "http://localhost:8084"
      flags = { "multi-tenancy" = "false" }
      authProvider = {
        "issuer-url"  = local.camunda_realm_issuer
        "backend-url" = local.camunda_realm_issuer
      }
      "component-presets" = local.identity_component_presets
    }
    keycloak = {
      url = local.keycloak_internal_url
      setup = {
        user     = "$${KEYCLOAK_SETUP_USER}"
        password = "$${KEYCLOAK_SETUP_PASSWORD}"
      }
      init = local.keycloak_init
      environment = {
        clients = [{
          name            = "Identity"
          id              = "camunda-identity"
          type            = "CONFIDENTIAL"
          secret          = "$${CAMUNDA_IDENTITY_CLIENT_SECRET}"
          "root-url"      = "http://localhost:8084"
          "redirect-uris" = ["/auth/login-callback"]
        }]
      }
      users = [{
        username  = "demo"
        password  = "demo"
        firstName = "Demo"
        lastName  = "User"
        email     = "demo@example.org"
        roles     = local.demo_user_roles
      }]
    }
    server  = { port = 8084 }
    camunda = { identity = { audience = "camunda-identity-resource-server" } }
  }

  identity_realm_json = jsonencode(local.identity_realm_config)
}
