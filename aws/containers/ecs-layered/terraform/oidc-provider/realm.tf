# The realm that the provider imports when it starts for the first time.
#
# Authorization is done on the Camunda side, so the realm holds no roles or groups: only the
# clients, with the audience and client ID mappers that Camunda requires, and the login user.

locals {
  realm_name = "camunda-platform"

  # The client ID claim: lets the Orchestration Cluster recognize machine-to-machine callers.
  client_id_mapper = {
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

  # The provider adds no API name to the audience by default, so each client needs an explicit mapper.
  audience_mapper = {
    for name, audience in {
      orchestration = local.orchestration_audience
      identity      = local.identity_audience
      hub_internal  = local.hub_audience_internal
      hub_public    = local.hub_audience_public
      } : name => {
      name            = "${name}-audience"
      protocol        = "openid-connect"
      protocolMapper  = "oidc-audience-mapper"
      consentRequired = false
      config = {
        "included.custom.audience"  = audience
        "access.token.claim"        = "true"
        "id.token.claim"            = "false"
        "introspection.token.claim" = "true"
        "lightweight.claim"         = "false"
      }
    }
  }

  orchestration_audience = "orchestration-api"
  identity_audience      = "camunda-identity-resource-server"
  hub_audience_internal  = "web-modeler-api"
  hub_audience_public    = "web-modeler-public-api"

  https_enabled = startswith(var.public_base_url, "https://")

  cluster_base_url = { for k, c in var.clusters : k => c.base_url != "" ? c.base_url : var.public_base_url }
  identity_base    = "${var.public_base_url}${var.identity_context_path}"

  orchestration_clients = [
    for k, c in var.clusters : {
      clientId                  = "orchestration-${k}"
      name                      = "Orchestration ${k}"
      enabled                   = true
      protocol                  = "openid-connect"
      publicClient              = false
      secret                    = random_password.orchestration_client[k].result
      standardFlowEnabled       = true # browser login for Operate and Tasklist
      serviceAccountsEnabled    = true
      directAccessGrantsEnabled = false
      rootUrl                   = local.cluster_base_url[k]
      redirectUris              = ["${local.cluster_base_url[k]}/sso-callback"]
      webOrigins                = ["+"]
      attributes                = { "post.logout.redirect.uris" = "${local.cluster_base_url[k]}/*" }
      protocolMappers           = [local.audience_mapper["orchestration"], local.client_id_mapper]
    }
  ]

  connectors_clients = [
    for k, c in var.clusters : {
      clientId                  = "connectors-${k}"
      name                      = "Connectors ${k}"
      enabled                   = true
      protocol                  = "openid-connect"
      publicClient              = false
      secret                    = random_password.connectors_client[k].result
      standardFlowEnabled       = false # machine to machine only
      serviceAccountsEnabled    = true
      directAccessGrantsEnabled = false
      protocolMappers           = [local.audience_mapper["orchestration"], local.client_id_mapper]
    }
  ]

  identity_client = {
    clientId                  = "camunda-identity"
    name                      = "Identity"
    enabled                   = true
    protocol                  = "openid-connect"
    publicClient              = false
    secret                    = random_password.identity_client.result
    standardFlowEnabled       = true
    serviceAccountsEnabled    = true
    directAccessGrantsEnabled = false
    rootUrl                   = local.identity_base
    redirectUris              = ["${local.identity_base}/auth/login-callback"]
    webOrigins                = ["+"]
    protocolMappers           = [local.audience_mapper["identity"], local.client_id_mapper]
  }

  # Camunda Hub is a public client (browser, PKCE). Its REST API validates both audiences.
  hub_client = {
    clientId                  = "web-modeler"
    name                      = "Web Modeler"
    enabled                   = true
    protocol                  = "openid-connect"
    publicClient              = true
    standardFlowEnabled       = true
    serviceAccountsEnabled    = false
    directAccessGrantsEnabled = false
    rootUrl                   = var.public_base_url
    redirectUris              = ["${var.public_base_url}${var.hub_context_path}/login-callback"]
    webOrigins                = ["+"]
    attributes                = { "post.logout.redirect.uris" = "${var.public_base_url}/*" }
    protocolMappers           = [local.audience_mapper["hub_internal"], local.audience_mapper["hub_public"], local.client_id_mapper]
  }

  realm = {
    realm   = local.realm_name
    enabled = true
    # Without TLS (a demo) the realm accepts HTTP. With TLS it keeps the stricter default.
    sslRequired           = local.https_enabled ? "external" : "none"
    registrationAllowed   = false
    loginWithEmailAllowed = true
    accessTokenLifespan   = 300

    clients = concat(
      local.orchestration_clients,
      local.connectors_clients,
      [local.identity_client],
      var.enable_camunda_hub ? [local.hub_client] : [],
    )

    users = [
      {
        username      = var.admin_username
        enabled       = true
        emailVerified = true
        firstName     = "Admin"
        lastName      = "User"
        email         = "${var.admin_username}@example.com"
        credentials = [
          {
            type      = "password"
            value     = random_password.realm_admin_user.result
            temporary = false
          },
        ]
      },
    ]
  }
}

resource "aws_secretsmanager_secret" "realm_import" {
  name                    = "${var.prefix}-oidc-provider-realm-import"
  description             = "Realm import JSON of the OIDC provider"
  recovery_window_in_days = 0
  kms_key_id              = var.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "realm_import" {
  secret_id     = aws_secretsmanager_secret.realm_import.id
  secret_string = jsonencode(local.realm)
}
