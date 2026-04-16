################################################################
#       Secrets Access Policies (Camunda App Secrets)          #
################################################################
# These policies grant the ECS task execution roles (created in the infra
# layer) permission to read the app-user secrets created in this layer.
# The Aurora admin secret ARN is also included because the DB seed task
# runs in region 0 and needs it.

data "aws_caller_identity" "current" {}

data "aws_region" "region_0" {}

data "aws_region" "region_1" {
  provider = aws.accepter
}

# Region 0 secrets access policy
resource "aws_iam_policy" "ecs_task_secrets_region_0" {
  name        = "${local.prefix_region_0}-ecs-task-secrets"
  description = "Allow ECS task execution role to read Secrets Manager values"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          local.infra.db_admin_secret_arn,
          aws_secretsmanager_secret.admin_user_password_region_0.arn,
          aws_secretsmanager_secret.connectors_password_region_0.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [local.infra.region_0_secrets_kms_key_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_secrets_region_0" {
  role       = local.infra.region_0_ecs_task_execution_role_name
  policy_arn = aws_iam_policy.ecs_task_secrets_region_0.arn
}

# Region 1 secrets access policy
resource "aws_iam_policy" "ecs_task_secrets_region_1" {
  provider = aws.accepter

  name        = "${local.prefix_region_1}-ecs-task-secrets"
  description = "Allow ECS task execution role to read Secrets Manager values"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.admin_user_password_region_1.arn,
          aws_secretsmanager_secret.connectors_password_region_1.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [local.infra.region_1_secrets_kms_key_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_secrets_region_1" {
  provider = aws.accepter

  role       = local.infra.region_1_ecs_task_execution_role_name
  policy_arn = aws_iam_policy.ecs_task_secrets_region_1.arn
}
