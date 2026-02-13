# Task execution role is managed centrally in workspace iam.tf
# Task role remains module-specific for service-specific permissions

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-connectors-task-role"

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
    Name = "${var.prefix}-connectors-task-role"
  }
}

# ECS Execute Command permissions
resource "aws_iam_policy" "ecs_exec_policy" {
  name = "${var.prefix}-connectors-exec-policy"

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
    Name = "${var.prefix}-connectors-exec-policy"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_exec_policy.arn
}

# CloudWatch Logs policy for connectors
resource "aws_iam_policy" "connectors_logs_policy" {
  name = "${var.prefix}-connectors-logs-policy"

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
    Name = "${var.prefix}-connectors-logs-policy"
  }
}

resource "aws_iam_role_policy_attachment" "connectors_logs_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.connectors_logs_policy.arn
}

# Attach extra task role policies
resource "aws_iam_role_policy_attachment" "task_role_policy_attachment" {
  count = length(var.extra_task_role_attachments)

  role       = aws_iam_role.ecs_task_role.name
  policy_arn = var.extra_task_role_attachments[count.index]
}
