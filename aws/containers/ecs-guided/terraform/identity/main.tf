# Identity stage. Today it covers two modes:
#
#   basic   no identity provider; the Orchestration Cluster and Connectors use built-in users.
#   oidc    your own OIDC provider (Entra ID, Okta, or any other OIDC-compliant provider).
#
# Both produce the same output, so the Camunda stage never knows which provider is behind
# it. An OIDC provider deployed on ECS by this architecture (parked, see the README)
# would be another producer of the same object.

locals {
  oidc_enabled = var.authentication_mode == "oidc"

  # Empty stand-in so that the expressions below can be evaluated, and fail in the
  # validation rather than on a null object, when external_oidc is missing.
  ext = var.external_oidc != null ? var.external_oidc : {
    issuer_uri                      = ""
    token_uri                       = ""
    orchestration_audience          = ""
    orchestration_client_id         = ""
    orchestration_client_secret_arn = ""
    connectors_client_id            = ""
    connectors_client_secret_arn    = ""
    username_claim                  = "preferred_username"
    client_id_claim                 = "client_id"
    connectors_token_scope          = ""
    client_secrets_kms_key_arn      = ""
  }

  oidc = local.oidc_enabled ? {
    issuer_uri      = local.ext.issuer_uri
    token_uri       = local.ext.token_uri
    audience        = local.ext.orchestration_audience
    redirect_uri    = "${var.public_base_url}/sso-callback"
    username_claim  = local.ext.username_claim
    client_id_claim = local.ext.client_id_claim
    admin_claim     = var.admin_claim_value
    orchestration = {
      client_id         = local.ext.orchestration_client_id
      client_secret_arn = local.ext.orchestration_client_secret_arn
    }
    connectors = {
      client_id         = local.ext.connectors_client_id
      client_secret_arn = local.ext.connectors_client_secret_arn
      token_scope       = local.ext.connectors_token_scope
    }
  } : null
}

resource "terraform_data" "validate" {
  lifecycle {
    precondition {
      condition     = !local.oidc_enabled || var.external_oidc != null
      error_message = "authentication_mode = oidc requires external_oidc."
    }
    precondition {
      condition     = local.oidc_enabled || var.external_oidc == null
      error_message = "external_oidc is only valid with authentication_mode = oidc."
    }
    precondition {
      condition = !local.oidc_enabled || alltrue([
        for v in [
          local.ext.issuer_uri,
          local.ext.token_uri,
          local.ext.orchestration_audience,
          local.ext.orchestration_client_id,
          local.ext.orchestration_client_secret_arn,
          local.ext.connectors_client_id,
          local.ext.connectors_client_secret_arn,
        ] : trimspace(v) != ""
      ])
      error_message = "Every required field of external_oidc must be non-empty: they flow into task settings and an empty value only fails at runtime."
    }
    precondition {
      condition     = !local.oidc_enabled || (trimspace(var.public_base_url) != "" && var.task_execution_role_name != "" && var.secrets_kms_key_arn != "")
      error_message = "authentication_mode = oidc requires public_base_url, task_execution_role_name and secrets_kms_key_arn."
    }
  }
}

# The execution role injects the client secrets into the tasks.
resource "aws_iam_policy" "client_secrets_read" {
  count = local.oidc_enabled ? 1 : 0

  name        = "${var.prefix}-oidc-client-secrets-read"
  description = "Allow the ECS task execution role to read the OIDC client secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          local.ext.orchestration_client_secret_arn,
          local.ext.connectors_client_secret_arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = distinct(compact([var.secrets_kms_key_arn, local.ext.client_secrets_kms_key_arn]))
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "client_secrets_read" {
  count = local.oidc_enabled ? 1 : 0

  role       = var.task_execution_role_name
  policy_arn = aws_iam_policy.client_secrets_read[0].arn
}
