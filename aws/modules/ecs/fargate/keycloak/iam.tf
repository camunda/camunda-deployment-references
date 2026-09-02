# Task execution role is managed centrally in workspace iam.tf
# Task role remains module-specific for service-specific permissions

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-keycloak-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.prefix}-keycloak-task-role"
  }
}

# ECS Execute Command permissions
resource "aws_iam_policy" "ecs_exec_policy" {
  name = "${var.prefix}-keycloak-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSSMMessaging"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.prefix}-keycloak-exec-policy"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_exec_policy.arn
}

# CloudWatch Logs policy for keycloak
resource "aws_iam_policy" "keycloak_logs_policy" {
  name = "${var.prefix}-keycloak-logs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:${var.log_group_name}",
          "arn:aws:logs:${var.aws_region}:*:log-group:${var.log_group_name}:*"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.prefix}-keycloak-logs-policy"
  }
}

resource "aws_iam_role_policy_attachment" "keycloak_logs_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.keycloak_logs_policy.arn
}

# Attach extra task role policies
resource "aws_iam_role_policy_attachment" "task_role_policy_attachment" {
  count = length(var.extra_task_role_attachments)

  role       = aws_iam_role.ecs_task_role.name
  policy_arn = var.extra_task_role_attachments[count.index]
}
