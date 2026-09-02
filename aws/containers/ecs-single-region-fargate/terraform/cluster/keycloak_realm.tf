# Keycloak realm import for the bundled provider.
#
# Builds the `camunda-platform` realm representation and stores it in a Secrets
# Manager secret that Keycloak reads on startup (KEYCLOAK_REALM_IMPORT_JSON ->
# --import-realm). Keycloak self-provisions the realm, so no Camunda component has to
# bootstrap it; the components then consume the generic local.oidc interface exactly
# as they would for an external provider.
#
# Authorization is done Camunda-side (CAMUNDA_SECURITY_INITIALIZATION_* /
# CAMUNDA_IDENTITY_*), so the realm carries no roles/groups — only clients (with the
# audience + client_id protocol mappers Camunda requires) and the `admin` login user.

locals {
  # client_id claim mapper: emits `client_id` for client-credentials tokens so
  # orchestration (client-id-claim=client_id) can map the connectors/orchestration
  # clients to roles. Shared by every client.
  kc_client_id_mapper = {
    name            = "client_id"
    protocol        = "openid-connect"
    protocolMapper  = "oidc-usersessionmodel-note-mapper"
    consentRequired = false
    config = {
      "user.session.note"         = "clientId"
      "claim.name"                = "client_id"
      "jsonType.label"            = "String"
      "access.token.claim"        = "true"
      "id.token.claim"            = "false"
      "introspection.token.claim" = "true"
    }
  }

  # Audience mapper factory: Keycloak does not add an API name to `aud` by default
  # (tokens carry aud=account and Camunda rejects them 401), so each client needs an
  # explicit oidc-audience-mapper. orchestration-api / camunda-identity-resource-server
  # are logical audience strings, hence included.custom.audience (not .client).
  kc_orchestration_api_mappers = [
    {
      name            = "orchestration-api-audience"
      protocol        = "openid-connect"
      protocolMapper  = "oidc-audience-mapper"
      consentRequired = false
      config = {
        "included.custom.audience"  = "orchestration-api"
        "access.token.claim"        = "true"
        "id.token.claim"            = "false"
        "introspection.token.claim" = "true"
        "lightweight.claim"         = "false"
      }
    },
    local.kc_client_id_mapper,
  ]

  kc_identity_resource_server_mappers = [
    {
      name            = "identity-resource-server-audience"
      protocol        = "openid-connect"
      protocolMapper  = "oidc-audience-mapper"
      consentRequired = false
      config = {
        "included.custom.audience"  = "camunda-identity-resource-server"
        "access.token.claim"        = "true"
        "id.token.claim"            = "false"
        "introspection.token.claim" = "true"
        "lightweight.claim"         = "false"
      }
    },
    local.kc_client_id_mapper,
  ]

  # Camunda Hub (Web Modeler) audience mappers: the restapi validates both the
  # internal and public API audiences, so the public client's tokens must carry them.
  kc_webmodeler_mappers = [
    {
      name            = "web-modeler-api-audience"
      protocol        = "openid-connect"
      protocolMapper  = "oidc-audience-mapper"
      consentRequired = false
      config = {
        "included.custom.audience"  = local.oidc.webmodeler.audience_internal
        "access.token.claim"        = "true"
        "id.token.claim"            = "false"
        "introspection.token.claim" = "true"
        "lightweight.claim"         = "false"
      }
    },
    {
      name            = "web-modeler-public-api-audience"
      protocol        = "openid-connect"
      protocolMapper  = "oidc-audience-mapper"
      consentRequired = false
      config = {
        "included.custom.audience"  = local.oidc.webmodeler.audience_public
        "access.token.claim"        = "true"
        "id.token.claim"            = "false"
        "introspection.token.claim" = "true"
        "lightweight.claim"         = "false"
      }
    },
    local.kc_client_id_mapper,
  ]

  # The Web Modeler client is registered only when Camunda Hub is deployed.
  webmodeler_client_enabled = var.enable_camunda_hub
  webmodeler_client = {
    clientId                  = local.oidc.webmodeler.client_id
    name                      = "Web Modeler"
    enabled                   = true
    protocol                  = "openid-connect"
    publicClient              = true # browser PKCE; the restapi is a resource server
    standardFlowEnabled       = true
    serviceAccountsEnabled    = false
    directAccessGrantsEnabled = false
    rootUrl                   = local.alb_base_url
    redirectUris              = ["${local.alb_base_url}${local.camunda_hub_context_path}/login-callback"]
    webOrigins                = ["+"]
    attributes                = { "post.logout.redirect.uris" = "${local.alb_base_url}/*" }
    protocolMappers           = local.kc_webmodeler_mappers
  }

  keycloak_realm = {
    realm   = "camunda-platform"
    enabled = true
    # HTTP demo: sslRequired=none. When the ALB terminates TLS the realm keeps the
    # stricter default and Keycloak trusts X-Forwarded-Proto (KC_PROXY_HEADERS).
    sslRequired           = local.alb_https_enabled ? "external" : "none"
    registrationAllowed   = false
    loginWithEmailAllowed = true
    accessTokenLifespan   = 300

    clients = concat([
      {
        clientId                  = "orchestration"
        name                      = "Orchestration"
        enabled                   = true
        protocol                  = "openid-connect"
        publicClient              = false
        secret                    = try(random_password.orchestration_oidc_client_secret[0].result, "")
        standardFlowEnabled       = true # browser login for Operate/Tasklist
        serviceAccountsEnabled    = true # also mapped as a client (internal m2m)
        directAccessGrantsEnabled = false
        rootUrl                   = local.alb_base_url
        redirectUris              = ["${local.alb_base_url}/sso-callback"]
        webOrigins                = ["+"]
        attributes                = { "post.logout.redirect.uris" = "${local.alb_base_url}/*" }
        protocolMappers           = local.kc_orchestration_api_mappers
      },
      {
        clientId                  = "connectors"
        name                      = "Connectors"
        enabled                   = true
        protocol                  = "openid-connect"
        publicClient              = false
        secret                    = try(random_password.connectors_oidc_client_secret[0].result, "")
        standardFlowEnabled       = false # m2m only
        serviceAccountsEnabled    = true  # client-credentials grant
        directAccessGrantsEnabled = false
        protocolMappers           = local.kc_orchestration_api_mappers
      },
      {
        clientId                  = "camunda-identity"
        name                      = "Identity"
        enabled                   = true
        protocol                  = "openid-connect"
        publicClient              = false
        secret                    = try(random_password.identity_client_secret[0].result, "")
        standardFlowEnabled       = true
        serviceAccountsEnabled    = true
        directAccessGrantsEnabled = false
        rootUrl                   = local.identity_public_base
        redirectUris              = ["${local.identity_public_base}/auth/login-callback"]
        webOrigins                = ["+"]
        protocolMappers           = local.kc_identity_resource_server_mappers
      },
      ],
      local.webmodeler_client_enabled ? [local.webmodeler_client] : [],
    )

    users = [
      {
        username      = "admin"
        enabled       = true
        emailVerified = true
        firstName     = "Admin"
        lastName      = "User"
        email         = "admin@example.com"
        credentials = [
          {
            type      = "password"
            value     = try(random_password.realm_admin_user_password[0].result, "")
            temporary = false
          },
        ]
      },
    ]
  }

  keycloak_realm_import_json = jsonencode(local.keycloak_realm)
}

resource "aws_secretsmanager_secret" "keycloak_realm_import" {
  count                   = local.deploy_bundled_keycloak ? 1 : 0
  name                    = "${var.prefix}-oc1-keycloak-realm-import"
  description             = "Keycloak realm import JSON for the camunda-platform realm (KEYCLOAK_REALM_IMPORT_JSON)"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn_effective
}

resource "aws_secretsmanager_secret_version" "keycloak_realm_import" {
  count         = local.deploy_bundled_keycloak ? 1 : 0
  secret_id     = aws_secretsmanager_secret.keycloak_realm_import[0].id
  secret_string = local.keycloak_realm_import_json
}
