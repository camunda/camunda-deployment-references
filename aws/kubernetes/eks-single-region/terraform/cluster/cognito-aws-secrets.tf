# AWS Secrets Manager for Cognito credentials
# Stores Cognito client secrets securely in AWS Secrets Manager

resource "aws_secretsmanager_secret" "cognito" {
  count       = var.enable_cognito ? 1 : 0
  name        = "${local.eks_cluster_name}/camunda/cognito"
  description = "Amazon Cognito credentials for Camunda Platform"

  tags = local.eks_tags
}

resource "aws_secretsmanager_secret_version" "cognito" {
  count     = var.enable_cognito ? 1 : 0
  secret_id = aws_secretsmanager_secret.cognito[0].id
  secret_string = jsonencode({
    user_pool_id                 = aws_cognito_user_pool.camunda[0].id
    issuer_url                   = "https://cognito-idp.${data.aws_region.current.id}.amazonaws.com/${aws_cognito_user_pool.camunda[0].id}"
    jwks_url                     = "https://cognito-idp.${data.aws_region.current.id}.amazonaws.com/${aws_cognito_user_pool.camunda[0].id}/.well-known/jwks.json"
    token_url                    = "https://${aws_cognito_user_pool_domain.camunda[0].domain}.auth.${data.aws_region.current.id}.amazoncognito.com/oauth2/token"
    authorization_url            = "https://${aws_cognito_user_pool_domain.camunda[0].domain}.auth.${data.aws_region.current.id}.amazoncognito.com/oauth2/authorize"
    domain_name                  = var.domain_name
    identity_initial_user_email  = var.identity_initial_user_email
    identity_client_id           = aws_cognito_user_pool_client.identity[0].id
    identity_client_secret       = aws_cognito_user_pool_client.identity[0].client_secret
    optimize_client_id           = aws_cognito_user_pool_client.optimize[0].id
    optimize_client_secret       = aws_cognito_user_pool_client.optimize[0].client_secret
    orchestration_client_id      = aws_cognito_user_pool_client.orchestration[0].id
    orchestration_client_secret  = aws_cognito_user_pool_client.orchestration[0].client_secret
    console_client_id            = var.enable_console ? aws_cognito_user_pool_client.console[0].id : ""
    connectors_client_id         = aws_cognito_user_pool_client.connectors[0].id
    connectors_client_secret     = aws_cognito_user_pool_client.connectors[0].client_secret
    webmodeler_ui_client_id      = var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_ui[0].id : ""
    webmodeler_api_client_id     = var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_api[0].id : ""
    webmodeler_api_client_secret = var.enable_webmodeler ? aws_cognito_user_pool_client.webmodeler_api[0].client_secret : ""
  })
}

# IAM Policy for accessing Cognito secrets
resource "aws_iam_policy" "cognito_secrets_access" {
  count       = var.enable_cognito ? 1 : 0
  name        = "${local.eks_cluster_name}-cognito-secrets-access"
  description = "Allows access to Cognito secrets in Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.cognito[0].arn
      }
    ]
  })

  tags = local.eks_tags
}

# Output for the secret ARN
output "cognito_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing Cognito credentials"
  value       = var.enable_cognito ? aws_secretsmanager_secret.cognito[0].arn : ""
}

output "cognito_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing Cognito credentials"
  value       = var.enable_cognito ? aws_secretsmanager_secret.cognito[0].name : ""
}

output "cognito_secrets_access_policy_arn" {
  description = "ARN of the IAM policy for accessing Cognito secrets"
  value       = var.enable_cognito ? aws_iam_policy.cognito_secrets_access[0].arn : ""
}
