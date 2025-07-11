# Docker Hub credentials stored in AWS Secrets Manager
# Only create these resources if Docker Hub credentials are provided
resource "aws_secretsmanager_secret" "docker_hub_credentials" {
  count                   = var.docker_hub_username != "" ? 1 : 0
  name                    = "${var.prefix}-docker-hub-credentials"
  description             = "Docker Hub credentials for ECS to pull images"
  recovery_window_in_days = 0
}

# You'll need to manually populate this secret with your Docker Hub credentials
# Format: {"username": "your-docker-hub-username", "password": "your-docker-hub-password"}
resource "aws_secretsmanager_secret_version" "docker_hub_credentials" {
  count     = var.docker_hub_username != "" ? 1 : 0
  secret_id = aws_secretsmanager_secret.docker_hub_credentials[0].id
  secret_string = jsonencode({
    username = var.docker_hub_username
    password = var.docker_hub_password
  })
}

# IAM policy for ECS to access Docker Hub credentials
resource "aws_iam_policy" "docker_hub_secrets_policy" {
  count = var.docker_hub_username != "" ? 1 : 0
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
          aws_secretsmanager_secret.docker_hub_credentials[0].arn
        ]
      }
    ]
  })
}

# Attach the policy to the ECS task execution role
resource "aws_iam_role_policy_attachment" "docker_hub_secrets_policy_attachment" {
  count      = var.docker_hub_username != "" ? 1 : 0
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.docker_hub_secrets_policy[0].arn
}
