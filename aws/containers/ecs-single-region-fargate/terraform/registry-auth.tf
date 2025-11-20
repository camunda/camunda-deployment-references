# Registry credentials stored in AWS Secrets Manager

# Applicable for any registry as the choice is dependent on the used image

# Only create these resources if registry credentials are provided
resource "aws_secretsmanager_secret" "registry_credentials" {
  count                   = var.registry_username != "" ? 1 : 0
  name                    = "${var.prefix}-docker-hub-credentials"
  description             = "Docker Hub credentials for ECS to pull images"
  recovery_window_in_days = 0
}

# You'll need to manually populate this secret with your Docker Hub credentials
resource "aws_secretsmanager_secret_version" "registry_credentials" {
  count     = var.registry_username != "" ? 1 : 0
  secret_id = aws_secretsmanager_secret.registry_credentials[0].id
  secret_string = jsonencode({
    username = var.registry_username
    password = var.registry_password
  })
}

# IAM policy for ECS to access Docker Hub credentials
resource "aws_iam_policy" "registry_secrets_policy" {
  count = var.registry_username != "" ? 1 : 0
  name  = "${var.prefix}-docker-hub-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.registry_credentials[0].arn
        ]
      }
    ]
  })
}
